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
      return Conversations::RequestClose.call(
        conversation: @conversation,
        intent_kind: "archive",
        occurred_at: @occurred_at
      ) if @force

      Conversations::WithRetainedLifecycleLock.call(
        conversation: @conversation,
        record: @conversation,
        retained_message: "must be retained before archival",
        expected_state: "active",
        lifecycle_message: "must be active before archival"
      ) do |conversation|
        ensure_conversation_quiescent!(conversation, stage: "archival")
        conversation.update!(lifecycle_state: "archived")
      end

      @conversation
    end

    private
  end
end
