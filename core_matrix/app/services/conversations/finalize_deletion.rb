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
      return @conversation if @conversation.deleted? && @conversation.canonical_store_reference.blank?

      raise_invalid!(@conversation, :deletion_state, "must be pending delete before finalization") unless @conversation.pending_delete?

      ApplicationRecord.transaction do
        @conversation.with_lock do
          validate_quiescent!
          @conversation.canonical_store_reference&.destroy!
          @conversation.update!(deletion_state: "deleted")
        end

        Conversations::ReconcileCloseOperation.call(conversation: @conversation)
      end

      CanonicalStores::GarbageCollectJob.perform_later
      @conversation.reload
    end

    private

    def validate_quiescent!
      ensure_mainline_stop_barrier_clear!(@conversation, stage: "final deletion")
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
