class CreateExecutionEnvironments < ActiveRecord::Migration[8.2]
  def change
    create_table :execution_environments do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :kind, null: false, default: "local"
      t.jsonb :connection_metadata, null: false, default: {}
      t.string :lifecycle_state, null: false, default: "active"

      t.timestamps
    end

    add_index :execution_environments, [:installation_id, :kind]
    add_index :execution_environments, :public_id, unique: true
  end
end
