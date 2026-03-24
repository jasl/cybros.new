class CreateWorkspaces < ActiveRecord::Migration[8.2]
  def change
    create_table :workspaces do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.belongs_to :user, null: false, foreign_key: true
      t.belongs_to :user_agent_binding, null: false, foreign_key: true
      t.string :name, null: false
      t.string :privacy, null: false, default: "private"
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end

    add_index :workspaces, [:installation_id, :user_id]
    add_index :workspaces, :user_agent_binding_id,
      unique: true,
      where: "is_default",
      name: "index_workspaces_on_user_agent_binding_id_default"
  end
end
