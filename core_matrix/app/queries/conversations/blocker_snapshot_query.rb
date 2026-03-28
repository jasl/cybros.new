module Conversations
  class BlockerSnapshotQuery
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, turns: conversation.turns)
      @conversation = conversation
      @turns = turns
    end

    def call
      ConversationBlockerSnapshot.new(
        retained: @conversation.retained?,
        active: @conversation.active?,
        closing: @conversation.closing?,
        queued_turn_count: turn_scope.where(lifecycle_state: "queued").count,
        active_turn_count: turn_scope.where(lifecycle_state: "active").count,
        active_workflow_count: workflow_run_scope.where(lifecycle_state: "active").count,
        queued_agent_task_count: agent_task_scope.where(lifecycle_state: "queued").count,
        active_agent_task_count: agent_task_scope.where(lifecycle_state: "running").count,
        open_interaction_count: interaction_scope.where(lifecycle_state: "open").count,
        open_blocking_interaction_count: interaction_scope.where(lifecycle_state: "open", blocking: true).count,
        running_turn_command_count: process_scope.where(lifecycle_state: "running", kind: "turn_command").count,
        running_process_count: process_scope.where(lifecycle_state: "running").count,
        running_background_process_count: process_scope.where(lifecycle_state: "running", kind: "background_service").count,
        detached_tool_process_count: 0,
        running_subagent_count: subagent_scope.where(lifecycle_state: %w[open close_requested], last_known_status: "running").count,
        active_execution_lease_count: execution_lease_scope.where(released_at: nil).count,
        degraded_close_count: degraded_close_count,
        descendant_lineage_blockers: descendant_lineage_blockers,
        root_store_blocker: root_store_blocker?,
        variable_provenance_blocker: variable_provenance_blocker?,
        import_provenance_blocker: import_provenance_blocker?
      )
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
      @subagent_scope ||= SubagentSession.where(
        owner_conversation_id: @conversation.id,
        origin_turn_id: turn_scope.select(:id)
      )
    end

    def execution_lease_scope
      @execution_lease_scope ||= ExecutionLease
        .joins(:workflow_run)
        .where(workflow_runs: { conversation_id: @conversation.id, turn_id: turn_scope.select(:id) })
    end

    def descendant_lineage_blockers
      @conversation.descendant_closures.where.not(descendant_conversation_id: @conversation.id).count
    end

    def root_store_blocker?
      CanonicalStore.where(root_conversation: @conversation).exists?
    end

    def variable_provenance_blocker?
      CanonicalVariable.where(source_conversation: @conversation).exists?
    end

    def import_provenance_blocker?
      ConversationImport.where(source_conversation: @conversation).exists?
    end

    def degraded_close_count
      process_close_failures + subagent_close_failures + task_close_failures
    end

    def process_close_failures
      process_scope
        .where(close_state: %w[failed closed])
        .where(close_outcome_kind: %w[residual_abandoned timed_out_forced])
        .count
    end

    def subagent_close_failures
      subagent_scope.where(close_state: "failed").count
    end

    def task_close_failures
      agent_task_scope.where(close_state: "failed").count
    end
  end
end
