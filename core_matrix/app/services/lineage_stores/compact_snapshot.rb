module LineageStores
  class CompactSnapshot
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      ApplicationRecord.transaction do
        @conversation.lock!
        reference = current_reference!
        reference.lock!
        current_snapshot = reference.lineage_store_snapshot

        compaction_snapshot = LineageStoreSnapshot.create!(
          lineage_store: current_snapshot.lineage_store,
          snapshot_kind: "compaction",
          depth: 0
        )
        visible_entry_rows(current_snapshot).each do |row|
          LineageStoreEntry.create!(
            lineage_store_snapshot: compaction_snapshot,
            key: row.fetch("key"),
            entry_kind: "set",
            lineage_store_value_id: row.fetch("lineage_store_value_id"),
            value_type: row.fetch("value_type"),
            value_bytesize: row.fetch("value_bytesize")
          )
        end
        reference.update!(lineage_store_snapshot: compaction_snapshot)
        compaction_snapshot
      end
    end

    private

    def current_reference!
      @conversation.lineage_store_reference ||
        raise(ActiveRecord::RecordNotFound, "lineage store reference is missing")
    end

    def visible_entry_rows(current_snapshot)
      ApplicationRecord.with_connection do |connection|
        connection.select_all(<<~SQL.squish).to_a
          WITH RECURSIVE snapshot_chain AS (
            SELECT id, base_snapshot_id, 0 AS traversal_rank
            FROM lineage_store_snapshots
            WHERE id = #{connection.quote(current_snapshot.id)}
            UNION ALL
            SELECT parents.id, parents.base_snapshot_id, snapshot_chain.traversal_rank + 1
            FROM lineage_store_snapshots parents
            INNER JOIN snapshot_chain ON snapshot_chain.base_snapshot_id = parents.id
          ),
          ranked_entries AS (
            SELECT entries.key,
                   entries.entry_kind,
                   entries.lineage_store_value_id,
                   entries.value_type,
                   entries.value_bytesize,
                   ROW_NUMBER() OVER (
                     PARTITION BY entries.key
                     ORDER BY snapshot_chain.traversal_rank ASC
                   ) AS row_number
            FROM snapshot_chain
            INNER JOIN lineage_store_entries entries
              ON entries.lineage_store_snapshot_id = snapshot_chain.id
          )
          SELECT key,
                 lineage_store_value_id,
                 value_type,
                 value_bytesize
          FROM ranked_entries
          WHERE row_number = 1
            AND entry_kind = 'set'
          ORDER BY key ASC
        SQL
      end
    end
  end
end
