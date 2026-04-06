module ConversationSupervision
  class BuildBoardCard
    def self.call(...)
      new(...).call
    end

    def initialize(conversation_supervision_state:)
      @conversation_supervision_state = conversation_supervision_state
    end

    def call
      {
        "conversation_id" => @conversation_supervision_state.target_conversation.public_id,
        "conversation_supervision_state_id" => @conversation_supervision_state.public_id,
        "board_lane" => @conversation_supervision_state.board_lane,
        "overall_state" => @conversation_supervision_state.overall_state,
        "last_terminal_state" => @conversation_supervision_state.last_terminal_state,
        "last_terminal_at" => @conversation_supervision_state.last_terminal_at&.iso8601,
        "current_owner_kind" => @conversation_supervision_state.current_owner_kind,
        "current_owner_public_id" => @conversation_supervision_state.current_owner_public_id,
        "request_summary" => @conversation_supervision_state.request_summary,
        "current_focus_summary" => @conversation_supervision_state.current_focus_summary,
        "recent_progress_summary" => @conversation_supervision_state.recent_progress_summary,
        "waiting_summary" => @conversation_supervision_state.waiting_summary,
        "blocked_summary" => @conversation_supervision_state.blocked_summary,
        "next_step_hint" => @conversation_supervision_state.next_step_hint,
        "last_progress_at" => @conversation_supervision_state.last_progress_at&.iso8601,
        "retry_due_at" => @conversation_supervision_state.retry_due_at&.iso8601,
        "active_plan_item_count" => @conversation_supervision_state.active_plan_item_count,
        "completed_plan_item_count" => @conversation_supervision_state.completed_plan_item_count,
        "active_subagent_count" => @conversation_supervision_state.active_subagent_count,
        "board_badges" => @conversation_supervision_state.board_badges,
      }.compact
    end
  end
end
