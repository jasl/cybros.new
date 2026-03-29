module LineageStores
  class GarbageCollect
    def self.call(...)
      new(...).call
    end

    def call
      reachable_snapshot_ids = load_reachable_snapshot_ids
      affected_root_conversation_ids = []

      ApplicationRecord.transaction do
        unreachable_snapshots = reachable_snapshot_ids.empty? ?
          LineageStoreSnapshot.all :
          LineageStoreSnapshot.where.not(id: reachable_snapshot_ids)
        unreachable_snapshot_ids = unreachable_snapshots.pluck(:id)

        if unreachable_snapshot_ids.any?
          LineageStoreEntry.where(lineage_store_snapshot_id: unreachable_snapshot_ids).delete_all
          LineageStoreSnapshot.where(id: unreachable_snapshot_ids).delete_all
        end

        LineageStoreValue.where.missing(:lineage_store_entries).delete_all
        unreachable_stores = LineageStore.where.missing(:lineage_store_snapshots)
        affected_root_conversation_ids = unreachable_stores.pluck(:root_conversation_id).compact
        unreachable_stores.delete_all
      end

      reconcile_deleted_conversations!(affected_root_conversation_ids)
    end

    private

    def reconcile_deleted_conversations!(conversation_ids)
      Conversation.where(id: conversation_ids).find_each do |conversation|
        next if conversation.unfinished_close_operation.blank?

        Conversations::ReconcileCloseOperation.call(conversation: conversation)
      end
    end

    def load_reachable_snapshot_ids
      ApplicationRecord.with_connection do |connection|
        connection.select_values(<<~SQL.squish).map(&:to_i)
          WITH RECURSIVE reachable_snapshots AS (
            SELECT lineage_store_snapshot_id AS id
            FROM lineage_store_references
            UNION
            SELECT snapshots.base_snapshot_id AS id
            FROM lineage_store_snapshots snapshots
            INNER JOIN reachable_snapshots
              ON snapshots.id = reachable_snapshots.id
            WHERE snapshots.base_snapshot_id IS NOT NULL
          )
          SELECT DISTINCT id
          FROM reachable_snapshots
          WHERE id IS NOT NULL
        SQL
      end
    end
  end
end
