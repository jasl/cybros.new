class CreateCapabilitySnapshots < ActiveRecord::Migration[8.2]
  def change
    create_table :capability_snapshots do |t|
      t.belongs_to :agent_deployment, null: false, foreign_key: true
      t.integer :version, null: false
      t.jsonb :protocol_methods, null: false, default: []
      t.jsonb :tool_catalog, null: false, default: []
      t.jsonb :profile_catalog, null: false, default: {}
      t.jsonb :config_schema_snapshot, null: false, default: {}
      t.jsonb :conversation_override_schema_snapshot, null: false, default: {}
      t.jsonb :default_config_snapshot, null: false, default: {}

      t.timestamps
    end

    add_index :capability_snapshots, [:agent_deployment_id, :version], unique: true
    add_foreign_key :agent_deployments, :capability_snapshots, column: :active_capability_snapshot_id
  end
end
