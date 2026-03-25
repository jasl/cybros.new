class CreateAgentInstallations < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_installations do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.belongs_to :owner_user, null: true, foreign_key: { to_table: :users }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :key, null: false
      t.string :display_name, null: false
      t.string :visibility, null: false, default: "global"
      t.string :lifecycle_state, null: false, default: "active"

      t.timestamps
    end

    add_index :agent_installations, [:installation_id, :key], unique: true
    add_index :agent_installations, [:installation_id, :visibility]
    add_index :agent_installations, :public_id, unique: true
  end
end
