class CreateAgents < ActiveRecord::Migration[8.2]
  def change
    create_table :agents do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.belongs_to :owner_user, null: true, foreign_key: { to_table: :users }
      t.bigint :current_agent_definition_version_id
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :key, null: false
      t.string :display_name, null: false
      t.string :visibility, null: false, default: "public"
      t.string :provisioning_origin, null: false, default: "system"
      t.string :lifecycle_state, null: false, default: "active"

      t.timestamps
    end

    add_index :agents, [:installation_id, :key], unique: true
    add_index :agents, [:installation_id, :visibility]
    add_index :agents, [:installation_id, :provisioning_origin]
    add_index :agents, [:installation_id, :lifecycle_state, :visibility, :owner_user_id], name: "idx_agents_visibility_lookup"
    add_index :agents, :current_agent_definition_version_id
    add_index :agents, :public_id, unique: true
  end
end
