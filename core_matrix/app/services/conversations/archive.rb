module Conversations
  class Archive
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, force: false, occurred_at: Time.current)
      @conversation = conversation
      @force = force
      @occurred_at = occurred_at
    end

    def call
      conversation = current_conversation

      return Conversations::RequestClose.call(
        conversation: conversation,
        intent_kind: "archive",
        occurred_at: @occurred_at
      ) if @force

      Conversations::WithRetainedLifecycleLock.call(
        conversation: conversation,
        record: conversation,
        retained_message: "must be retained before archival",
        expected_state: "active",
        lifecycle_message: "must be active before archival"
      ) do |locked_conversation|
        Conversations::ValidateQuiescence.call(
          conversation: locked_conversation,
          stage: "archival",
          mainline_only: false
        )
        locked_conversation.update!(lifecycle_state: "archived")
      end

      conversation
    end

    private

    def current_conversation
      @current_conversation ||= Conversation.find(@conversation.id)
    end
  end
end
