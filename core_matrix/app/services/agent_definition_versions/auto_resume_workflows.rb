module AgentDefinitionVersions
  class AutoResumeWorkflows
    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:)
      @agent_definition_version = agent_definition_version
    end

    def call
      return [] unless resumable_agent_definition_version_state?

      workflow_runs_scope.filter_map do |workflow_run|
        next unless scheduling_ready?

        recovery_plan = ExecutionIdentityRecovery::BuildPlan.call(
          agent_definition_version: @agent_definition_version,
          workflow_run: workflow_run
        )

        if recovery_plan.resume?
          workflow_run if resume_workflow!(workflow_run, recovery_plan)
        else
          escalate_to_manual_recovery!(workflow_run, recovery_plan)
          nil
        end
      end
    end

    private

    def workflow_runs_scope
      WorkflowRun
        .joins(:conversation)
        .includes(:turn)
        .joins(turn: :agent_definition_version)
        .where(lifecycle_state: "active", wait_state: "waiting", wait_reason_kind: "agent_unavailable")
        .where(conversations: { deletion_state: "retained" })
        .where(agent_definition_versions: { agent_id: @agent_definition_version.agent_id })
        .order(:id)
    end

    def resumable_agent_definition_version_state?
      active_agent_connection&.healthy? && active_agent_connection&.auto_resume_eligible?
    end

    def scheduling_ready?
      active_agent_connection&.scheduling_ready?
    end

    def active_agent_connection
      @active_agent_connection ||= @agent_definition_version.active_agent_connection
    end

    def resume_workflow!(workflow_run, recovery_plan)
      ExecutionIdentityRecovery::ApplyPlan.call(
        agent_definition_version: @agent_definition_version,
        workflow_run: workflow_run,
        recovery_plan: recovery_plan
      )
    end

    def escalate_to_manual_recovery!(workflow_run, recovery_plan)
      ExecutionIdentityRecovery::ApplyPlan.call(
        agent_definition_version: @agent_definition_version,
        workflow_run: workflow_run,
        recovery_plan: recovery_plan
      )
    end
  end
end
