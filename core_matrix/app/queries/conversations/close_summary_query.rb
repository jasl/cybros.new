module Conversations
  class CloseSummaryQuery
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      dependency_blockers = Conversations::DependencyBlockersQuery.call(conversation: @conversation)

      {
        mainline: {
          active_turn_count: active_turn_count,
          active_workflow_count: active_workflow_count,
          active_agent_task_count: active_agent_task_count,
          open_blocking_interaction_count: open_blocking_interaction_count,
          running_turn_command_count: running_turn_command_count,
          running_subagent_count: running_subagent_count,
        },
        tail: {
          running_background_process_count: running_background_process_count,
          detached_tool_process_count: 0,
          degraded_close_count: degraded_close_count,
        },
        dependencies: {
          descendant_lineage_blockers: dependency_blockers.descendant_lineage_blockers,
          root_store_blocker: dependency_blockers.root_store_blocker,
          variable_provenance_blocker: dependency_blockers.variable_provenance_blocker,
          import_provenance_blocker: dependency_blockers.import_provenance_blocker,
        },
      }
    end

    private

    def active_turn_count
      Turn.where(conversation: @conversation, lifecycle_state: "active").count
    end

    def active_workflow_count
      WorkflowRun.where(conversation: @conversation, lifecycle_state: "active").count
    end

    def active_agent_task_count
      AgentTaskRun.where(conversation: @conversation, lifecycle_state: "running").count
    end

    def open_blocking_interaction_count
      HumanInteractionRequest.where(conversation: @conversation, lifecycle_state: "open", blocking: true).count
    end

    def running_turn_command_count
      ProcessRun.where(conversation: @conversation, lifecycle_state: "running", kind: "turn_command").count
    end

    def running_subagent_count
      SubagentRun.joins(:workflow_run).where(workflow_runs: { conversation_id: @conversation.id }, lifecycle_state: "running").count
    end

    def running_background_process_count
      ProcessRun.where(conversation: @conversation, lifecycle_state: "running", kind: "background_service").count
    end

    def degraded_close_count
      process_close_failures + subagent_close_failures + task_close_failures
    end

    def process_close_failures
      ProcessRun.where(conversation: @conversation)
        .where(close_state: %w[failed closed])
        .where(close_outcome_kind: %w[residual_abandoned timed_out_forced])
        .count
    end

    def subagent_close_failures
      SubagentRun.joins(:workflow_run)
        .where(workflow_runs: { conversation_id: @conversation.id })
        .where(close_state: "failed")
        .count
    end

    def task_close_failures
      AgentTaskRun.where(conversation: @conversation, close_state: "failed").count
    end
  end
end
