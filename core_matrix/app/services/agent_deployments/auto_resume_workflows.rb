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
        resume_plan = auto_resume_plan_for(workflow_run.turn)

        if @deployment.eligible_for_auto_resume? && resume_plan.present?
          resume_workflow!(workflow_run, resume_plan)
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
        .joins(:conversation)
        .includes(:turn)
        .joins(turn: :agent_deployment)
        .where(lifecycle_state: "active", wait_state: "waiting", wait_reason_kind: "agent_unavailable")
        .where(conversations: { deletion_state: "retained" })
        .where(agent_deployments: { agent_installation_id: @deployment.agent_installation_id })
        .order(:id)
    end

    def auto_resume_plan_for(turn)
      return { rebind_turn: false } if @deployment.runtime_identity_matches?(turn)
      return unless compatible_rotated_replacement?(turn)

      resolved_model_selection_snapshot = resolve_rotated_model_selection_snapshot(turn)
      return if resolved_model_selection_snapshot.blank?

      {
        rebind_turn: true,
        resolved_model_selection_snapshot: resolved_model_selection_snapshot,
      }
    end

    def resume_workflow!(workflow_run, resume_plan)
      ApplicationRecord.transaction do
        rebind_turn!(workflow_run.turn, resume_plan) if resume_plan.fetch(:rebind_turn)

        workflow_run.update!(
          AgentDeployments::UnavailablePauseState.resume_attributes(
            workflow_run: workflow_run
          )
        )
      end
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
      if rotated_replacement_for?(turn)
        return "capability_contract_drift" unless @deployment.preserves_capability_contract?(turn)
        return "selector_resolution_drift" if resolve_rotated_model_selection_snapshot(turn).blank?
        return "auto_resume_not_permitted" unless @deployment.auto_resume_eligible?

        return "deployment_rotation_drift"
      end

      return "fingerprint_drift" if @deployment.fingerprint != turn.pinned_deployment_fingerprint
      return "capability_snapshot_version_drift" if @deployment.capability_snapshot_version != turn.pinned_capability_snapshot_version
      return "auto_resume_not_permitted" unless @deployment.auto_resume_eligible?

      "runtime_drift"
    end

    def resumable_deployment_state?
      @deployment.healthy? && @deployment.active_capability_snapshot.present?
    end

    def compatible_rotated_replacement?(turn)
      rotated_replacement_for?(turn) && @deployment.preserves_capability_contract?(turn)
    end

    def rotated_replacement_for?(turn)
      current_deployment = turn.agent_deployment
      current_deployment.present? &&
        current_deployment.id != @deployment.id &&
        current_deployment.same_logical_agent?(@deployment)
    end

    def resolve_rotated_model_selection_snapshot(turn)
      selector_source = turn.resolved_model_selection_snapshot["selector_source"] || "conversation"
      selector = turn.normalized_selector
      probe_turn = turn.dup
      probe_turn.installation = turn.installation
      probe_turn.conversation = turn.conversation
      probe_turn.agent_deployment = @deployment
      probe_turn.pinned_deployment_fingerprint = @deployment.fingerprint
      probe_turn.resolved_config_snapshot = turn.resolved_config_snapshot.deep_dup
      probe_turn.resolved_model_selection_snapshot = turn.resolved_model_selection_snapshot.deep_dup

      Workflows::ResolveModelSelector.call(
        turn: probe_turn,
        selector_source: selector_source,
        selector: selector
      )
    rescue ActiveRecord::RecordInvalid
      nil
    end

    def rebind_turn!(turn, resume_plan)
      turn.update!(
        agent_deployment: @deployment,
        pinned_deployment_fingerprint: @deployment.fingerprint,
        resolved_model_selection_snapshot: resume_plan.fetch(:resolved_model_selection_snapshot)
      )
      turn.update!(resolved_config_snapshot: Workflows::ContextAssembler.call(turn: turn))
    end
  end
end
