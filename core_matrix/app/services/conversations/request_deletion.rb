module Conversations
  class RequestDeletion
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, occurred_at: Time.current)
      @conversation = conversation
      @occurred_at = occurred_at
    end

    def call
      return @conversation if @conversation.deleted?

      ApplicationRecord.transaction do
        @conversation.with_lock do
          if @conversation.retained?
            @conversation.update!(
              deletion_state: "pending_delete",
              deleted_at: @occurred_at
            )
          end

          Conversations::QuiesceActiveWork.call(
            conversation: @conversation,
            reason_kind: "conversation_deleted",
            revoke_publication: true,
            occurred_at: @occurred_at
          )
        end
      end

      @conversation.reload
    end
  end
end
