module AgentDefinitionVersions
  class MarkUnavailable
    Result = Struct.new(:agent_definition_version, :workflow_runs, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, severity:, reason:, occurred_at: Time.current)
      @agent_definition_version = agent_definition_version
      @severity = severity.to_s
      @reason = reason.to_s
      @occurred_at = occurred_at
    end

    def call
      ApplicationRecord.transaction do
        @agent_definition_version.reload
        if resolved_agent_connection.present?
          AgentConnections::RecordHeartbeat.call(
            agent_connection: resolved_agent_connection,
            health_status: next_health_status,
            health_metadata: resolved_agent_connection.health_metadata,
            auto_resume_eligible: next_auto_resume_eligible,
            unavailability_reason: @reason,
            occurred_at: @occurred_at
          )
        end

        affected_workflows = workflow_runs_scope.filter_map do |workflow_run|
          workflow_run if apply_wait_state!(workflow_run)
        end

        AuditLog.record!(
          installation: @agent_definition_version.installation,
          action: audit_action,
          subject: @agent_definition_version,
          metadata: {
            "severity" => @severity,
            "reason" => @reason,
            "workflow_run_ids" => affected_workflows.map(&:id),
          }
        )

        Result.new(agent_definition_version: @agent_definition_version, workflow_runs: affected_workflows)
      end
    end

    private

    def apply_wait_state!(workflow_run)
      applied = false

      Workflows::WithLockedWorkflowContext.call(workflow_run: workflow_run) do |current_workflow_run, turn|
        next unless pausable_workflow_state?(current_workflow_run, turn)

        current_workflow_run.update!(
          AgentDefinitionVersions::UnavailablePauseState.pause_attributes(
            workflow_run: current_workflow_run,
            agent_definition_version: @agent_definition_version,
            recovery_state: recovery_state,
            reason: @reason,
            occurred_at: @occurred_at,
            wait_reason_kind: next_wait_reason_kind
          )
        )
        applied = true
      end

      applied
    end

    def pausable_workflow_state?(workflow_run, turn)
      workflow_run.active? &&
        workflow_run.cancellation_reason_kind.blank? &&
        turn.cancellation_reason_kind.blank? &&
        turn.agent_definition_version_id == @agent_definition_version.id
    end

    def workflow_runs_scope
      WorkflowRun
        .joins(:turn)
        .where(lifecycle_state: "active")
        .where(turns: { agent_definition_version_id: @agent_definition_version.id })
    end

    def next_health_status
      return "degraded" if transient?

      "offline"
    end

    def next_auto_resume_eligible
      return @agent_definition_version.auto_resume_eligible? if transient?

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
      return "agent_definition_version.degraded" if transient?

      "agent_definition_version.paused_agent_unavailable"
    end

    def transient?
      @severity == "transient"
    end

    def resolved_agent_connection
      @resolved_agent_connection ||= @agent_definition_version.active_agent_connection || @agent_definition_version.most_recent_agent_connection
    end
  end
end
