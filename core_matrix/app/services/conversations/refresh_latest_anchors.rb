module Conversations
  class RefreshLatestAnchors
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, activity_at: nil)
      @conversation = conversation
      @activity_at = activity_at
    end

    def call
      latest_turn = @conversation.turns.order(sequence: :desc, id: :desc).first
      latest_active_turn = @conversation.turns.where(lifecycle_state: "active").order(sequence: :desc, id: :desc).first
      latest_active_workflow_run = @conversation.workflow_runs.where(lifecycle_state: "active").order(created_at: :desc, id: :desc).first
      latest_message = @conversation.messages.order(created_at: :desc, id: :desc).first
      activity_timestamp = [
        @conversation.last_activity_at,
        @activity_at,
        latest_message&.created_at,
        latest_turn&.created_at,
        latest_active_workflow_run&.created_at,
      ].compact.max
      updated_at = Time.current

      @conversation.latest_turn = latest_turn
      @conversation.latest_active_turn = latest_active_turn
      @conversation.latest_active_workflow_run = latest_active_workflow_run
      @conversation.latest_message = latest_message
      @conversation.last_activity_at = activity_timestamp
      @conversation.updated_at = updated_at
      @conversation.update_columns(
        latest_turn_id: latest_turn&.id,
        latest_active_turn_id: latest_active_turn&.id,
        latest_active_workflow_run_id: latest_active_workflow_run&.id,
        latest_message_id: latest_message&.id,
        last_activity_at: activity_timestamp,
        updated_at: updated_at
      )
      @conversation
    end
  end
end
