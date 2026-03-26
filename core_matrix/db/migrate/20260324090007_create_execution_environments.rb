class CreateExecutionEnvironments < ActiveRecord::Migration[8.2]
  def change
    create_table :execution_environments do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :kind, null: false, default: "local"
      t.string :environment_fingerprint, null: false
      t.jsonb :connection_metadata, null: false, default: {}
      t.jsonb :capability_payload, null: false, default: {}
      t.jsonb :tool_catalog, null: false, default: []
      t.string :lifecycle_state, null: false, default: "active"

      t.timestamps
    end

    add_index :execution_environments, [:installation_id, :environment_fingerprint], unique: true, name: "idx_execution_environments_installation_fingerprint"
    add_index :execution_environments, [:installation_id, :kind]
    add_index :execution_environments, :public_id, unique: true
  end
end
