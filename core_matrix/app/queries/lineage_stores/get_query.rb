module LineageStores
  class GetQuery
    include LineageStores::QuerySupport

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

        build_visible_value(row, typed_value_payload: row.fetch("typed_value_payload"))
      end
    end

    private

    def sql(connection)
      <<~SQL.squish
        #{snapshot_chain_cte_sql(connection)}
        SELECT entries.key,
               entries.entry_kind,
               entries.value_type,
               entries.value_bytesize,
               entries.created_at,
               entries.updated_at,
               values.typed_value_payload
        FROM snapshot_chain
        INNER JOIN lineage_store_entries entries
          ON entries.lineage_store_snapshot_id = snapshot_chain.id
        LEFT JOIN lineage_store_values values
          ON values.id = entries.lineage_store_value_id
        WHERE entries.key = #{quoted_key(connection)}
        ORDER BY snapshot_chain.traversal_rank ASC
        LIMIT 1
      SQL
    end

    def quoted_key(connection) = connection.quote(@key)
  end
end
