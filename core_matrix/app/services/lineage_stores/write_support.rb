module LineageStores
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

      LineageStoreEntry.create!(
        { lineage_store_snapshot: write_snapshot }.merge(entry_attributes)
      )
      reference.update!(lineage_store_snapshot: write_snapshot)

      write_snapshot
    end

    def compact_if_needed!(reference)
      return reference unless reference.lineage_store_snapshot.depth >= MAX_SNAPSHOT_DEPTH

      LineageStores::CompactSnapshot.call(conversation: @conversation)
      reference.reload
    end

    def current_reference!
      @conversation.lineage_store_reference ||
        raise(ActiveRecord::RecordNotFound, "lineage store reference is missing")
    end

    def create_write_snapshot!(reference)
      current_snapshot = reference.lineage_store_snapshot

      LineageStoreSnapshot.create!(
        lineage_store: current_snapshot.lineage_store,
        base_snapshot: current_snapshot,
        snapshot_kind: "write",
        depth: current_snapshot.depth + 1
      )
    end
  end
end
