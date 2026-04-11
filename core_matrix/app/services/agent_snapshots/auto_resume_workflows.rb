module AgentSnapshots
  class AutoResumeWorkflows
    def self.call(...)
      new(...).call
    end

    def initialize(agent_snapshot:)
      @agent_snapshot = agent_snapshot
    end

    def call
      return [] unless resumable_agent_snapshot_state?

      workflow_runs_scope.filter_map do |workflow_run|
        next unless @agent_snapshot.eligible_for_scheduling?

        recovery_plan = AgentSnapshots::BuildRecoveryPlan.call(
          agent_snapshot: @agent_snapshot,
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
        .joins(turn: :agent_snapshot)
        .where(lifecycle_state: "active", wait_state: "waiting", wait_reason_kind: "agent_unavailable")
        .where(conversations: { deletion_state: "retained" })
        .where(agent_snapshots: { agent_id: @agent_snapshot.agent_id })
        .order(:id)
    end

    def resumable_agent_snapshot_state?
      @agent_snapshot.healthy? && @agent_snapshot.auto_resume_eligible?
    end

    def resume_workflow!(workflow_run, recovery_plan)
      AgentSnapshots::ApplyRecoveryPlan.call(
        agent_snapshot: @agent_snapshot,
        workflow_run: workflow_run,
        recovery_plan: recovery_plan
      )
    end

    def escalate_to_manual_recovery!(workflow_run, recovery_plan)
      AgentSnapshots::ApplyRecoveryPlan.call(
        agent_snapshot: @agent_snapshot,
        workflow_run: workflow_run,
        recovery_plan: recovery_plan
      )
    end
  end
end
