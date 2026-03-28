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

      ApplicationRecord.transaction do
        @conversation.with_lock do
          Conversations::ValidateArchiveTarget.call(
            conversation: @conversation,
            record: @conversation
          )
          ensure_conversation_quiescent!(@conversation, stage: "archival")
          @conversation.update!(lifecycle_state: "archived")
        end
      end

      @conversation
    end

    private
  end
end
