class CreateAgentSnapshots < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_snapshots do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.belongs_to :agent, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :fingerprint, null: false
      t.string :protocol_version, null: false
      t.string :sdk_version, null: false
      t.jsonb :protocol_methods, null: false, default: []
      t.jsonb :tool_catalog, null: false, default: []
      t.jsonb :profile_catalog, null: false, default: {}
      t.jsonb :config_schema_snapshot, null: false, default: {}
      t.jsonb :conversation_override_schema_snapshot, null: false, default: {}
      t.jsonb :default_config_snapshot, null: false, default: {}

      t.timestamps
    end

    add_index :agent_snapshots, [:installation_id, :fingerprint], unique: true
    add_index :agent_snapshots, :public_id, unique: true
  end
end
