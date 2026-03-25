module CanonicalStores
  class DeleteKey
    include Conversations::RetentionGuard

    MAX_SNAPSHOT_DEPTH = 32

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, key:)
      @conversation = conversation
      @key = key.to_s
    end

    def call
      ApplicationRecord.transaction do
        @conversation.lock!
        ensure_conversation_retained!(@conversation, message: "must be retained for conversation-local writes")
        reference = current_reference!
        reference.lock!

        return if CanonicalStores::GetQuery.call(reference_owner: @conversation, key: @key).blank?

        reference = compact_if_needed!(reference)
        current_snapshot = reference.canonical_store_snapshot
        write_snapshot = CanonicalStoreSnapshot.create!(
          canonical_store: current_snapshot.canonical_store,
          base_snapshot: current_snapshot,
          snapshot_kind: "write",
          depth: current_snapshot.depth + 1
        )
        CanonicalStoreEntry.create!(
          canonical_store_snapshot: write_snapshot,
          key: @key,
          entry_kind: "tombstone"
        )
        reference.update!(canonical_store_snapshot: write_snapshot)
      end
    end

    private

    def compact_if_needed!(reference)
      return reference unless reference.canonical_store_snapshot.depth >= MAX_SNAPSHOT_DEPTH

      CanonicalStores::CompactSnapshot.call(conversation: @conversation)
      reference.reload
    end

    def current_reference!
      @conversation.canonical_store_reference ||
        raise(ActiveRecord::RecordNotFound, "canonical store reference is missing")
    end
  end
end
