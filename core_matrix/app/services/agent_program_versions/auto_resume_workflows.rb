module AgentProgramVersions
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
        next unless @deployment.eligible_for_scheduling?

        recovery_plan = AgentProgramVersions::BuildRecoveryPlan.call(
          deployment: @deployment,
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
        .joins(turn: :agent_program_version)
        .where(lifecycle_state: "active", wait_state: "waiting", wait_reason_kind: "agent_unavailable")
        .where(conversations: { deletion_state: "retained" })
        .where(agent_program_versions: { agent_program_id: @deployment.agent_program_id })
        .order(:id)
    end

    def resumable_deployment_state?
      @deployment.healthy? && @deployment.auto_resume_eligible?
    end

    def resume_workflow!(workflow_run, recovery_plan)
      AgentProgramVersions::ApplyRecoveryPlan.call(
        deployment: @deployment,
        workflow_run: workflow_run,
        recovery_plan: recovery_plan
      )
    end

    def escalate_to_manual_recovery!(workflow_run, recovery_plan)
      AgentProgramVersions::ApplyRecoveryPlan.call(
        deployment: @deployment,
        workflow_run: workflow_run,
        recovery_plan: recovery_plan
      )
    end
  end
end
