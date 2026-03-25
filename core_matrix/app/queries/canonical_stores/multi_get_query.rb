module CanonicalStores
  class MultiGetQuery
    def self.call(...)
      new(...).call
    end

    def initialize(reference_owner:, keys:)
      @reference_owner = reference_owner
      @keys = Array(keys).map(&:to_s)
    end

    def call
      return {} if @keys.empty?

      ApplicationRecord.with_connection do |connection|
        entry_rows = connection.select_all(entries_sql(connection)).to_a
        visible_rows = entry_rows.index_by { |row| row.fetch("key") }
        value_rows_by_id = load_value_rows(connection, visible_rows.values)

        @keys.index_with do |key|
          row = visible_rows[key]
          next if row.blank? || row["entry_kind"] == "tombstone"

          build_visible_value(row, value_rows_by_id.fetch(row.fetch("canonical_store_value_id")))
        end
      end
    end

    private

    def build_visible_value(row, value_row)
      CanonicalStores::VisibleValue.new(
        key: row.fetch("key"),
        typed_value_payload: decode_payload(value_row.fetch("typed_value_payload")),
        value_type: row.fetch("value_type"),
        value_bytesize: row.fetch("value_bytesize"),
        created_at: row.fetch("created_at"),
        updated_at: row.fetch("updated_at")
      )
    end

    def load_value_rows(connection, rows)
      value_ids = rows
        .reject { |row| row["entry_kind"] == "tombstone" }
        .filter_map { |row| row["canonical_store_value_id"] }
        .uniq
      return {} if value_ids.empty?

      connection.select_all(<<~SQL.squish).index_by { |row| row.fetch("id") }
        SELECT id, typed_value_payload
        FROM canonical_store_values
        WHERE id IN (#{value_ids.map { |id| connection.quote(id) }.join(", ")})
      SQL
    end

    def entries_sql(connection)
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
        ),
        ranked_entries AS (
          SELECT entries.key,
                 entries.entry_kind,
                 entries.canonical_store_value_id,
                 entries.value_type,
                 entries.value_bytesize,
                 entries.created_at,
                 entries.updated_at,
                 ROW_NUMBER() OVER (
                   PARTITION BY entries.key
                   ORDER BY snapshot_chain.traversal_rank ASC
                 ) AS row_number
          FROM snapshot_chain
          INNER JOIN canonical_store_entries entries
            ON entries.canonical_store_snapshot_id = snapshot_chain.id
          WHERE entries.key IN (#{quoted_keys(connection)})
        )
        SELECT key,
               entry_kind,
               canonical_store_value_id,
               value_type,
               value_bytesize,
               created_at,
               updated_at
        FROM ranked_entries
        WHERE row_number = 1
      SQL
    end

    def quoted_keys(connection)
      @keys.map { |key| connection.quote(key) }.join(", ")
    end

    def quoted_owner_id(connection) = connection.quote(@reference_owner.id)

    def quoted_owner_type(connection) = connection.quote(@reference_owner.class.base_class.name)

    def decode_payload(payload)
      payload.is_a?(String) ? ActiveSupport::JSON.decode(payload) : payload
    end
  end
end
