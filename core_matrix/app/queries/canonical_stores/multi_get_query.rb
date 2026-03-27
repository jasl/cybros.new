module CanonicalStores
  class MultiGetQuery
    include CanonicalStores::QuerySupport

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
      super(row, typed_value_payload: value_row.fetch("typed_value_payload"))
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
        #{snapshot_chain_cte_sql(connection)},
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
  end
end
