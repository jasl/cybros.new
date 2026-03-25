module Conversations
  class Archive
    include Conversations::RetentionGuard
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
      ApplicationRecord.transaction do
        @conversation.with_lock do
          ensure_conversation_retained!(@conversation, message: "must be retained before archival")
          raise_invalid!(@conversation, :lifecycle_state, "must be active before archival") unless @conversation.active?
          force_quiesce! if @force
          ensure_conversation_quiescent!(@conversation, stage: "archival")
          @conversation.update!(lifecycle_state: "archived")
        end
      end

      @conversation
    end

    private

    def force_quiesce!
      Conversations::QuiesceActiveWork.call(
        conversation: @conversation,
        reason_kind: "conversation_archived",
        occurred_at: @occurred_at
      )
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
