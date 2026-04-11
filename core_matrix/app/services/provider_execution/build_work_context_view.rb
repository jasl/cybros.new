module ProviderExecution
  class BuildWorkContextView
    ACTIVE_TASK_LIFECYCLE_STATES = %w[queued running].freeze
    ACTIVE_CHILD_OBSERVED_STATUSES = %w[running waiting].freeze
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:)
      @workflow_node = workflow_node
      @workflow_run = workflow_node.workflow_run
      @conversation = workflow_node.conversation
      @turn = workflow_node.turn
    end

    def call
      {
        "conversation_id" => @conversation.public_id,
        "turn_id" => @turn.public_id,
        "primary_turn_todo" => primary_turn_todo,
        "active_children" => active_children,
        "supervision_snapshot" => supervision_snapshot,
        "supervisor_guidance" => supervisor_guidance,
      }.compact
    end

    private

    def primary_turn_todo
      current_turn_todo.slice("plan_summary", "plan_view")
    end

    def active_children
      active_child_connections.map do |connection|
        task_run = active_child_task_runs_by_conversation_id[connection.conversation_id]
        plan_summary = child_plan_summary(task_run)

        {
          "subagent_connection_id" => connection.public_id,
          "conversation_id" => connection.conversation.public_id,
          "scope" => connection.scope,
          "profile_key" => connection.profile_key,
          "observed_status" => connection.observed_status,
          "supervision_state" => connection.supervision_state,
          "request_summary" => plan_summary&.fetch("goal_summary", nil) || task_run&.request_summary || connection.request_summary,
          "current_focus_summary" => plan_summary&.fetch("current_item_title", nil) || task_run&.current_focus_summary || connection.current_focus_summary,
          "waiting_summary" => task_run&.waiting_summary || connection.waiting_summary,
          "blocked_summary" => task_run&.blocked_summary || connection.blocked_summary,
          "next_step_hint" => task_run&.next_step_hint || connection.next_step_hint,
          "plan_summary" => plan_summary,
        }.compact
      end
    end

    def supervision_snapshot
      board_card = ConversationSupervision::BuildBoardCard.call(
        conversation_supervision_state: supervision_state
      )

      {
        "supervision_state_id" => board_card["conversation_supervision_state_id"],
        "board_lane" => board_card["board_lane"],
        "overall_state" => board_card["overall_state"],
        "last_terminal_state" => board_card["last_terminal_state"],
        "last_terminal_at" => board_card["last_terminal_at"],
        "current_owner_kind" => board_card["current_owner_kind"],
        "current_owner_public_id" => board_card["current_owner_public_id"],
        "request_summary" => board_card["request_summary"],
        "current_focus_summary" => board_card["current_focus_summary"],
        "recent_progress_summary" => board_card["recent_progress_summary"],
        "waiting_summary" => board_card["waiting_summary"],
        "blocked_summary" => board_card["blocked_summary"],
        "next_step_hint" => board_card["next_step_hint"],
        "last_progress_at" => board_card["last_progress_at"],
        "retry_due_at" => board_card["retry_due_at"],
        "active_plan_item_count" => board_card["active_plan_item_count"],
        "completed_plan_item_count" => board_card["completed_plan_item_count"],
        "active_child_count" => board_card["active_subagent_count"],
        "board_badges" => board_card["board_badges"],
      }.compact
    end

    def supervisor_guidance
      @supervisor_guidance ||= ConversationControl::BuildGuidanceProjection.call(
        conversation: @conversation
      )
    end

    def current_turn_todo
      @current_turn_todo ||= ConversationSupervision::BuildCurrentTurnTodo.call(
        conversation: @conversation,
        active_agent_task_run: active_agent_task_run,
        workflow_run: @workflow_run
      )
    end

    def active_agent_task_run
      @active_agent_task_run ||= AgentTaskRun
        .where(conversation: @conversation, lifecycle_state: ACTIVE_TASK_LIFECYCLE_STATES)
        .includes(turn_todo_plan: :turn_todo_plan_items)
        .order(created_at: :desc)
        .first
    end

    def active_child_connections
      @active_child_connections ||= @conversation.owned_subagent_connections
        .includes(:conversation)
        .close_pending_or_open
        .where(observed_status: ACTIVE_CHILD_OBSERVED_STATUSES)
        .order(:created_at)
        .to_a
    end

    def active_child_task_runs_by_conversation_id
      @active_child_task_runs_by_conversation_id ||= active_child_connections.each_with_object({}) do |connection, index|
        task_run = AgentTaskRun
          .where(conversation: connection.conversation, lifecycle_state: ACTIVE_TASK_LIFECYCLE_STATES)
          .includes(turn_todo_plan: :turn_todo_plan_items)
          .order(created_at: :desc)
          .first
        next if task_run.blank?

        index[connection.conversation_id] = task_run
      end
    end

    def supervision_state
      @supervision_state ||= Conversations::UpdateSupervisionState.call(
        conversation: @conversation,
        occurred_at: snapshot_occurred_at
      )
    end

    def snapshot_occurred_at
      @snapshot_occurred_at ||= @workflow_run.updated_at || @turn.updated_at || Time.current
    end

    def child_plan_summary(task_run)
      return if task_run&.turn_todo_plan.blank?

      TurnTodoPlans::BuildCompactView.call(turn_todo_plan: task_run.turn_todo_plan)
    end
  end
end
