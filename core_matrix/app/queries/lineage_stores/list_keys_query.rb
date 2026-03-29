module LineageStores
  class ListKeysQuery
    include LineageStores::QuerySupport

    DEFAULT_LIMIT = 100

    def self.call(...)
      new(...).call
    end

    def initialize(reference_owner:, cursor:, limit:)
      @reference_owner = reference_owner
      @cursor = cursor.presence
      @limit = limit
    end

    def call
      ApplicationRecord.with_connection do |connection|
        rows = connection.select_all(sql(connection)).to_a
        visible_rows = rows.first(limit_value)

        LineageStores::KeyPage.new(
          items: visible_rows.map { |row| build_key_metadata(row) },
          next_cursor: rows.size > limit_value ? visible_rows.last&.fetch("key") : nil
        )
      end
    end

    private

    def build_key_metadata(row)
      LineageStores::KeyMetadata.new(
        key: row.fetch("key"),
        entry_kind: row.fetch("entry_kind"),
        value_type: row.fetch("value_type"),
        value_bytesize: row.fetch("value_bytesize"),
        created_at: row.fetch("created_at"),
        updated_at: row.fetch("updated_at")
      )
    end

    def cursor_clause(connection)
      return "1=1" if @cursor.blank?

      "key > #{connection.quote(@cursor)}"
    end

    def limit_value
      requested = @limit.present? ? Integer(@limit) : DEFAULT_LIMIT

      requested.clamp(1, DEFAULT_LIMIT)
    rescue ArgumentError, TypeError
      DEFAULT_LIMIT
    end

    def sql(connection)
      <<~SQL.squish
        #{snapshot_chain_cte_sql(connection)},
        ranked_entries AS (
          SELECT entries.key,
                 entries.entry_kind,
                 entries.value_type,
                 entries.value_bytesize,
                 entries.created_at,
                 entries.updated_at,
                 ROW_NUMBER() OVER (
                   PARTITION BY entries.key
                   ORDER BY snapshot_chain.traversal_rank ASC
                 ) AS row_number
          FROM snapshot_chain
          INNER JOIN lineage_store_entries entries
            ON entries.lineage_store_snapshot_id = snapshot_chain.id
        ),
        visible_entries AS (
          SELECT key,
                 entry_kind,
                 value_type,
                 value_bytesize,
                 created_at,
                 updated_at
          FROM ranked_entries
          WHERE row_number = 1
            AND entry_kind <> 'tombstone'
        )
        SELECT key,
               entry_kind,
               value_type,
               value_bytesize,
               created_at,
               updated_at
        FROM visible_entries
        WHERE #{cursor_clause(connection)}
        ORDER BY key ASC
        LIMIT #{limit_value + 1}
      SQL
    end
  end
end
