module Conversations
  class FinalizeDeletion
    include Conversations::WorkQuiescenceGuard

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      conversation = current_conversation

      return conversation if conversation.deleted? && conversation.lineage_store_reference.blank?

      raise_invalid!(conversation, :deletion_state, "must be pending delete before finalization") unless conversation.pending_delete?

      ApplicationRecord.transaction do
        conversation.with_lock do
          locked_conversation = conversation.reload
          validate_quiescent!(locked_conversation)
          locked_conversation.lineage_store_reference&.destroy!
          locked_conversation.update!(deletion_state: "deleted")
        end

        Conversations::ReconcileCloseOperation.call(conversation: conversation)
      end

      LineageStores::GarbageCollectJob.perform_later
      conversation.reload
    end

    private

    def current_conversation
      @current_conversation ||= Conversation.find(@conversation.id)
    end

    def validate_quiescent!(conversation)
      ensure_mainline_stop_barrier_clear!(conversation, stage: "final deletion")
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
