module Conversations
  class RefreshLatestTurnAnchors
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, turn:, message: nil, activity_at: nil)
      @conversation = conversation
      @turn = turn
      @message = message
      @activity_at = activity_at || @message&.created_at || @turn.created_at
    end

    def call
      activity_timestamp = [
        @conversation.last_activity_at,
        @activity_at,
        @message&.created_at,
        @turn.created_at,
      ].compact.max
      updated_at = Time.current
      latest_active_turn_id = @turn.active? ? @turn.id : @conversation.latest_active_turn_id

      @conversation.latest_turn = @turn
      @conversation.latest_active_turn = @turn if latest_active_turn_id == @turn.id
      @conversation.latest_message = @message if @message.present?
      @conversation.last_activity_at = activity_timestamp
      @conversation.updated_at = updated_at
      update_attributes = {
        latest_turn_id: @turn.id,
        latest_active_turn_id: latest_active_turn_id,
        last_activity_at: activity_timestamp,
        updated_at: updated_at,
      }
      update_attributes[:latest_message_id] = @message.id if @message.present?

      @conversation.update_columns(update_attributes)
      @conversation
    end
  end
end
