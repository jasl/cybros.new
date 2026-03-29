class CreateLineageStores < ActiveRecord::Migration[8.2]
  def change
    create_table :lineage_stores do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.references :root_conversation,
        null: false,
        foreign_key: { to_table: :conversations },
        index: { unique: true }

      t.timestamps
    end
    create_table :lineage_store_snapshots do |t|
      t.references :lineage_store, null: false, foreign_key: true
      t.references :base_snapshot, foreign_key: { to_table: :lineage_store_snapshots }
      t.integer :depth, null: false
      t.string :snapshot_kind, null: false

      t.timestamps
    end

    add_check_constraint :lineage_store_snapshots,
      "(snapshot_kind IN ('root', 'write', 'compaction'))",
      name: "chk_lineage_store_snapshots_kind"
    add_check_constraint :lineage_store_snapshots,
      "((snapshot_kind IN ('root', 'compaction') AND base_snapshot_id IS NULL AND depth = 0) OR (snapshot_kind = 'write' AND base_snapshot_id IS NOT NULL AND depth >= 1))",
      name: "chk_lineage_store_snapshots_shape"

    create_table :lineage_store_values do |t|
      t.jsonb :typed_value_payload, null: false, default: {}
      t.string :payload_sha256, null: false
      t.integer :payload_bytesize, null: false

      t.timestamps
    end

    add_index :lineage_store_values, :payload_sha256
    add_check_constraint :lineage_store_values,
      "(payload_bytesize >= 0 AND payload_bytesize <= 2097152)",
      name: "chk_lineage_store_values_payload_bytesize"

    create_table :lineage_store_entries do |t|
      t.references :lineage_store_snapshot, null: false, foreign_key: true
      t.string :key, null: false
      t.string :entry_kind, null: false
      t.references :lineage_store_value, foreign_key: true
      t.string :value_type
      t.integer :value_bytesize

      t.timestamps
    end

    add_index :lineage_store_entries,
      [:lineage_store_snapshot_id, :key],
      unique: true,
      name: "idx_lineage_store_entries_snapshot_key"
    add_check_constraint :lineage_store_entries,
      "(entry_kind IN ('set', 'tombstone'))",
      name: "chk_lineage_store_entries_kind"
    add_check_constraint :lineage_store_entries,
      "(octet_length(key) >= 1 AND octet_length(key) <= 128)",
      name: "chk_lineage_store_entries_key_bytes"
    add_check_constraint :lineage_store_entries,
      "((entry_kind = 'set' AND lineage_store_value_id IS NOT NULL AND value_type IS NOT NULL AND value_bytesize IS NOT NULL AND value_bytesize >= 0 AND value_bytesize <= 2097152) OR (entry_kind = 'tombstone' AND lineage_store_value_id IS NULL AND value_type IS NULL AND value_bytesize IS NULL))",
      name: "chk_lineage_store_entries_value_shape"

    create_table :lineage_store_references do |t|
      t.references :lineage_store_snapshot, null: false, foreign_key: true
      t.string :owner_type, null: false
      t.bigint :owner_id, null: false

      t.timestamps
    end

    add_index :lineage_store_references,
      [:owner_type, :owner_id],
      unique: true,
      name: "idx_lineage_store_references_owner"
  end
end
