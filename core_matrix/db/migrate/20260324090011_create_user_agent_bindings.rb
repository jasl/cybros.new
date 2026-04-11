class CreateUserAgentBindings < ActiveRecord::Migration[8.2]
  def change
    create_table :user_agent_bindings do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.belongs_to :user, null: false, foreign_key: true
      t.belongs_to :agent, null: false, foreign_key: true
      t.jsonb :preferences, null: false, default: {}

      t.timestamps
    end

    add_index :user_agent_bindings, [:user_id, :agent_id], unique: true
    add_index :user_agent_bindings, [:installation_id, :user_id]
  end
end
