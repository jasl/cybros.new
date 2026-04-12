class CreateExecutionRuntimes < ActiveRecord::Migration[8.2]
  def change
    create_table :execution_runtimes do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.belongs_to :owner_user, null: true, foreign_key: { to_table: :users }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :visibility, null: false, default: "public"
      t.string :provisioning_origin, null: false, default: "system"
      t.string :kind, null: false, default: "local"
      t.string :display_name, null: false
      t.string :lifecycle_state, null: false, default: "active"

      t.timestamps
    end

    add_index :execution_runtimes, [:installation_id, :kind]
    add_index :execution_runtimes, [:installation_id, :visibility]
    add_index :execution_runtimes, [:installation_id, :provisioning_origin]
    add_index :execution_runtimes, :public_id, unique: true

    add_reference :agents,
      :default_execution_runtime,
      foreign_key: { to_table: :execution_runtimes }
  end
end
