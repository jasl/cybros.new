class CreateExecutorPrograms < ActiveRecord::Migration[8.2]
  def change
    create_table :executor_programs do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :kind, null: false, default: "local"
      t.string :display_name, null: false
      t.string :executor_fingerprint, null: false
      t.jsonb :connection_metadata, null: false, default: {}
      t.jsonb :capability_payload, null: false, default: {}
      t.jsonb :tool_catalog, null: false, default: []
      t.string :lifecycle_state, null: false, default: "active"

      t.timestamps
    end

    add_index :executor_programs, [:installation_id, :executor_fingerprint], unique: true, name: "idx_executor_programs_installation_fingerprint"
    add_index :executor_programs, [:installation_id, :kind]
    add_index :executor_programs, :public_id, unique: true

    add_reference :agent_programs,
      :default_executor_program,
      foreign_key: { to_table: :executor_programs }
  end
end
