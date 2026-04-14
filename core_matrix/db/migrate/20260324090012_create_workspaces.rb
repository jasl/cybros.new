class CreateWorkspaces < ActiveRecord::Migration[8.2]
  def change
    create_table :workspaces do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.belongs_to :user, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :name, null: false
      t.string :privacy, null: false, default: "private"
      t.boolean :is_default, null: false, default: false
      t.jsonb :config, null: false, default: {}
      t.jsonb :disabled_capabilities, null: false, default: []

      t.timestamps
    end

    add_index :workspaces, [:installation_id, :user_id]
    add_index :workspaces, :public_id, unique: true
    add_index :workspaces, [:installation_id, :user_id],
      unique: true,
      where: "is_default",
      name: "idx_workspaces_default_per_user"
  end
end
