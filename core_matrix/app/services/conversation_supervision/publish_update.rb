module ConversationSupervision
  class PublishUpdate
    EVENT_NAME = "conversation_supervision.updated".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation_supervision_state:, previous_attributes:, latest_feed_entry: nil)
      @conversation_supervision_state = conversation_supervision_state
      @previous_attributes = previous_attributes || {}
      @latest_feed_entry = latest_feed_entry
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
        "board_badges" => @conversation_supervision_state.board_badges,
        "latest_feed_entry" => serialized_feed_entry,
      }.compact

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

    def serialized_feed_entry
      return if @latest_feed_entry.blank?

      {
        "conversation_supervision_feed_entry_id" => @latest_feed_entry.public_id,
        "turn_id" => @latest_feed_entry.target_turn&.public_id,
        "sequence" => @latest_feed_entry.sequence,
        "event_kind" => @latest_feed_entry.event_kind,
        "summary" => @latest_feed_entry.summary,
        "occurred_at" => @latest_feed_entry.occurred_at.iso8601,
      }.compact
    end
  end
end
