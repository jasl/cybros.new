module AgentDeployments
  class AutoResumeWorkflows
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:)
      @deployment = deployment
    end

    def call
      return [] unless resumable_deployment_state?

      workflow_runs_scope.filter_map do |workflow_run|
        if @deployment.eligible_for_auto_resume? && @deployment.runtime_identity_matches?(workflow_run.turn)
          resume_workflow!(workflow_run)
          workflow_run
        elsif @deployment.eligible_for_scheduling?
          escalate_to_manual_recovery!(workflow_run, drift_reason_for(workflow_run.turn))
          nil
        end
      end
    end

    private

    def workflow_runs_scope
      WorkflowRun
        .includes(:turn)
        .joins(:turn)
        .where(lifecycle_state: "active", wait_state: "waiting", wait_reason_kind: "agent_unavailable")
        .where(turns: { agent_deployment_id: @deployment.id })
        .order(:id)
    end

    def resume_workflow!(workflow_run)
      workflow_run.update!(
        wait_state: "ready",
        wait_reason_kind: nil,
        wait_reason_payload: {},
        waiting_since_at: nil,
        blocking_resource_type: nil,
        blocking_resource_id: nil
      )
    end

    def escalate_to_manual_recovery!(workflow_run, drift_reason)
      workflow_run.update!(
        wait_reason_kind: "manual_recovery_required",
        wait_reason_payload: workflow_run.wait_reason_payload.merge(
          "recovery_state" => "paused_agent_unavailable",
          "drift_reason" => drift_reason,
          "reason" => @deployment.unavailability_reason.presence || workflow_run.wait_reason_payload["reason"]
        )
      )

      AuditLog.record!(
        installation: @deployment.installation,
        action: "agent_deployment.paused_agent_unavailable",
        subject: @deployment,
        metadata: {
          "reason" => workflow_run.wait_reason_payload["reason"],
          "drift_reason" => drift_reason,
          "workflow_run_ids" => [workflow_run.id],
        }
      )
    end

    def drift_reason_for(turn)
      return "fingerprint_drift" if @deployment.fingerprint != turn.pinned_deployment_fingerprint
      return "capability_snapshot_version_drift" if @deployment.capability_snapshot_version != turn.pinned_capability_snapshot_version
      return "auto_resume_not_permitted" unless @deployment.auto_resume_eligible?

      "runtime_drift"
    end

    def resumable_deployment_state?
      @deployment.healthy? && @deployment.active_capability_snapshot.present?
    end
  end
end
