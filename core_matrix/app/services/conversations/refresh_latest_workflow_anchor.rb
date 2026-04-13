module Conversations
  class RefreshLatestWorkflowAnchor
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, workflow_run:, activity_at: nil)
      @conversation = conversation
      @workflow_run = workflow_run
      @activity_at = activity_at || workflow_run.created_at
    end

    def call
      activity_timestamp = [
        @conversation.last_activity_at,
        @activity_at,
        @workflow_run.created_at,
      ].compact.max
      updated_at = Time.current

      @conversation.latest_active_workflow_run = @workflow_run
      @conversation.last_activity_at = activity_timestamp
      @conversation.updated_at = updated_at
      @conversation.update_columns(
        latest_active_workflow_run_id: @workflow_run.id,
        last_activity_at: activity_timestamp,
        updated_at: updated_at
      )
      @conversation
    end
  end
end
