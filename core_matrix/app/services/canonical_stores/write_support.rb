module CanonicalStores
  module WriteSupport
    MAX_SNAPSHOT_DEPTH = 32

    private

    def with_locked_reference_for_write(&block)
      ApplicationRecord.transaction do
        Conversations::WithMutableStateLock.call(
          conversation: @conversation,
          record: @conversation,
          retained_message: "must be retained for conversation-local writes",
          active_message: "must be active for conversation-local writes",
          closing_message: "must not mutate conversation state while close is in progress"
        ) do |conversation|
          @conversation = conversation
          reference = current_reference!
          reference.lock!

          yield conversation, reference
        end
      end
    end

    def append_write_entry!(reference:, entry_attributes:)
      reference = compact_if_needed!(reference)
      write_snapshot = create_write_snapshot!(reference)

      CanonicalStoreEntry.create!(
        { canonical_store_snapshot: write_snapshot }.merge(entry_attributes)
      )
      reference.update!(canonical_store_snapshot: write_snapshot)

      write_snapshot
    end

    def compact_if_needed!(reference)
      return reference unless reference.canonical_store_snapshot.depth >= MAX_SNAPSHOT_DEPTH

      CanonicalStores::CompactSnapshot.call(conversation: @conversation)
      reference.reload
    end

    def current_reference!
      @conversation.canonical_store_reference ||
        raise(ActiveRecord::RecordNotFound, "canonical store reference is missing")
    end

    def create_write_snapshot!(reference)
      current_snapshot = reference.canonical_store_snapshot

      CanonicalStoreSnapshot.create!(
        canonical_store: current_snapshot.canonical_store,
        base_snapshot: current_snapshot,
        snapshot_kind: "write",
        depth: current_snapshot.depth + 1
      )
    end
  end
end
