class CreateExecutionRuntimes < ActiveRecord::Migration[8.2]
  def change
    create_table :execution_runtimes do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :kind, null: false, default: "local"
      t.string :display_name, null: false
      t.string :execution_runtime_fingerprint, null: false
      t.jsonb :connection_metadata, null: false, default: {}
      t.jsonb :capability_payload, null: false, default: {}
      t.jsonb :tool_catalog, null: false, default: []
      t.string :lifecycle_state, null: false, default: "active"

      t.timestamps
    end

    add_index :execution_runtimes, [:installation_id, :execution_runtime_fingerprint], unique: true, name: "idx_execution_runtimes_installation_fingerprint"
    add_index :execution_runtimes, [:installation_id, :kind]
    add_index :execution_runtimes, :public_id, unique: true

    add_reference :agents,
      :default_execution_runtime,
      foreign_key: { to_table: :execution_runtimes }
  end
end
