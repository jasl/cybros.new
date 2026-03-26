module Conversations
  class WorkBarrierQuery
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, turns: conversation.turns)
      @conversation = conversation
      @turns = turns
    end

    def call
      {
        queued_turn_count: turn_scope.where(lifecycle_state: "queued").count,
        active_turn_count: turn_scope.where(lifecycle_state: "active").count,
        active_workflow_count: workflow_run_scope.where(lifecycle_state: "active").count,
        queued_agent_task_count: agent_task_scope.where(lifecycle_state: "queued").count,
        active_agent_task_count: agent_task_scope.where(lifecycle_state: "running").count,
        open_interaction_count: interaction_scope.where(lifecycle_state: "open").count,
        open_blocking_interaction_count: interaction_scope.where(lifecycle_state: "open", blocking: true).count,
        running_turn_command_count: process_scope.where(lifecycle_state: "running", kind: "turn_command").count,
        running_process_count: process_scope.where(lifecycle_state: "running").count,
        running_subagent_count: subagent_scope.where(lifecycle_state: "running").count,
        active_execution_lease_count: execution_lease_scope.where(released_at: nil).count,
      }
    end

    private

    def turn_scope
      @turn_scope ||= @turns.where(conversation_id: @conversation.id)
    end

    def workflow_run_scope
      @workflow_run_scope ||= WorkflowRun.where(conversation_id: @conversation.id, turn_id: turn_scope.select(:id))
    end

    def agent_task_scope
      @agent_task_scope ||= AgentTaskRun.where(conversation_id: @conversation.id, turn_id: turn_scope.select(:id))
    end

    def interaction_scope
      @interaction_scope ||= HumanInteractionRequest.where(conversation_id: @conversation.id, turn_id: turn_scope.select(:id))
    end

    def process_scope
      @process_scope ||= ProcessRun.where(conversation_id: @conversation.id, turn_id: turn_scope.select(:id))
    end

    def subagent_scope
      @subagent_scope ||= SubagentRun.joins(:workflow_run).where(workflow_runs: { conversation_id: @conversation.id, turn_id: turn_scope.select(:id) })
    end

    def execution_lease_scope
      @execution_lease_scope ||= ExecutionLease.joins(:workflow_run).where(workflow_runs: { conversation_id: @conversation.id, turn_id: turn_scope.select(:id) })
    end
  end
end
