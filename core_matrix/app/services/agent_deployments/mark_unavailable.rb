module AgentDeployments
  class MarkUnavailable
    Result = Struct.new(:deployment, :workflow_runs, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, severity:, reason:, occurred_at: Time.current)
      @deployment = deployment
      @severity = severity.to_s
      @reason = reason.to_s
      @occurred_at = occurred_at
    end

    def call
      ApplicationRecord.transaction do
        @deployment.reload
        @deployment.update!(
          health_status: next_health_status,
          auto_resume_eligible: next_auto_resume_eligible,
          unavailability_reason: @reason,
          last_health_check_at: @occurred_at
        )

        affected_workflows = workflow_runs_scope.map do |workflow_run|
          apply_wait_state!(workflow_run)
          workflow_run
        end

        AuditLog.record!(
          installation: @deployment.installation,
          action: audit_action,
          subject: @deployment,
          metadata: {
            "severity" => @severity,
            "reason" => @reason,
            "workflow_run_ids" => affected_workflows.map(&:id),
          }
        )

        Result.new(deployment: @deployment, workflow_runs: affected_workflows)
      end
    end

    private

    def apply_wait_state!(workflow_run)
      workflow_run.update!(
        AgentDeployments::UnavailablePauseState.pause_attributes(
          workflow_run: workflow_run,
          deployment: @deployment,
          recovery_state: recovery_state,
          reason: @reason,
          occurred_at: @occurred_at,
          wait_reason_kind: next_wait_reason_kind
        )
      )
    end

    def workflow_runs_scope
      WorkflowRun
        .joins(:turn)
        .where(lifecycle_state: "active")
        .where(turns: { agent_deployment_id: @deployment.id })
    end

    def next_health_status
      return "degraded" if transient?

      "offline"
    end

    def next_auto_resume_eligible
      return @deployment.auto_resume_eligible if transient?

      false
    end

    def next_wait_reason_kind
      return "agent_unavailable" if transient?

      "manual_recovery_required"
    end

    def recovery_state
      return "transient_outage" if transient?

      "paused_agent_unavailable"
    end

    def audit_action
      return "agent_deployment.degraded" if transient?

      "agent_deployment.paused_agent_unavailable"
    end

    def transient?
      @severity == "transient"
    end
  end
end
