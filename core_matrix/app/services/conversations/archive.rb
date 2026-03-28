module Conversations
  class Archive
    include Conversations::WorkQuiescenceGuard

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
        ensure_conversation_quiescent!(locked_conversation, stage: "archival")
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
