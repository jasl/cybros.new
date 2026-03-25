module CanonicalStores
  class GetQuery
    def self.call(...)
      new(...).call
    end

    def initialize(reference_owner:, key:)
      @reference_owner = reference_owner
      @key = key.to_s
    end

    def call
      ApplicationRecord.with_connection do |connection|
        row = connection.select_one(sql(connection))
        next if row.blank? || row["entry_kind"] == "tombstone"

        build_visible_value(row)
      end
    end

    private

    def build_visible_value(row)
      CanonicalStores::VisibleValue.new(
        key: row.fetch("key"),
        typed_value_payload: decode_payload(row.fetch("typed_value_payload")),
        value_type: row.fetch("value_type"),
        value_bytesize: row.fetch("value_bytesize"),
        created_at: row.fetch("created_at"),
        updated_at: row.fetch("updated_at")
      )
    end

    def sql(connection)
      <<~SQL.squish
        WITH RECURSIVE snapshot_chain AS (
          SELECT snapshots.id, snapshots.base_snapshot_id, 0 AS traversal_rank
          FROM canonical_store_references store_refs
          INNER JOIN canonical_store_snapshots snapshots
            ON snapshots.id = store_refs.canonical_store_snapshot_id
          WHERE store_refs.owner_type = #{quoted_owner_type(connection)}
            AND store_refs.owner_id = #{quoted_owner_id(connection)}
          UNION ALL
          SELECT parents.id, parents.base_snapshot_id, snapshot_chain.traversal_rank + 1
          FROM canonical_store_snapshots parents
          INNER JOIN snapshot_chain ON snapshot_chain.base_snapshot_id = parents.id
        )
        SELECT entries.key,
               entries.entry_kind,
               entries.value_type,
               entries.value_bytesize,
               entries.created_at,
               entries.updated_at,
               values.typed_value_payload
        FROM snapshot_chain
        INNER JOIN canonical_store_entries entries
          ON entries.canonical_store_snapshot_id = snapshot_chain.id
        LEFT JOIN canonical_store_values values
          ON values.id = entries.canonical_store_value_id
        WHERE entries.key = #{quoted_key(connection)}
        ORDER BY snapshot_chain.traversal_rank ASC
        LIMIT 1
      SQL
    end

    def quoted_key(connection) = connection.quote(@key)

    def quoted_owner_id(connection) = connection.quote(@reference_owner.id)

    def quoted_owner_type(connection) = connection.quote(@reference_owner.class.base_class.name)

    def decode_payload(payload)
      payload.is_a?(String) ? ActiveSupport::JSON.decode(payload) : payload
    end
  end
end
