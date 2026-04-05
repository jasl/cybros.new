module ConversationSupervision
  class PublishUpdate
    EVENT_NAME = "conversation_supervision.updated".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation_supervision_state:, previous_attributes:)
      @conversation_supervision_state = conversation_supervision_state
      @previous_attributes = previous_attributes || {}
    end

    def call
      return if material_snapshot(@previous_attributes) == material_snapshot(current_attributes)

      payload = {
        "conversation_id" => @conversation_supervision_state.target_conversation.public_id,
        "conversation_supervision_state_id" => @conversation_supervision_state.public_id,
        "board_lane" => @conversation_supervision_state.board_lane,
        "overall_state" => @conversation_supervision_state.overall_state,
        "last_terminal_state" => @conversation_supervision_state.last_terminal_state,
        "last_terminal_at" => @conversation_supervision_state.last_terminal_at&.iso8601,
        "active_plan_item_count" => @conversation_supervision_state.active_plan_item_count,
        "completed_plan_item_count" => @conversation_supervision_state.completed_plan_item_count,
        "active_subagent_count" => @conversation_supervision_state.active_subagent_count,
        "board_badges" => @conversation_supervision_state.board_badges
      }

      ActiveSupport::Notifications.instrument(EVENT_NAME, payload)
      payload
    end

    private

    def current_attributes
      @conversation_supervision_state.attributes
    end

    def material_snapshot(attributes)
      attributes.slice(
        "board_lane",
        "overall_state",
        "last_terminal_state",
        "last_terminal_at",
        "current_owner_kind",
        "current_owner_public_id",
        "current_focus_summary",
        "recent_progress_summary",
        "active_plan_item_count",
        "completed_plan_item_count",
        "active_subagent_count",
        "board_badges",
        "retry_due_at"
      )
    end
  end
end
