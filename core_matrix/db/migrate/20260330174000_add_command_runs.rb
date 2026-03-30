class AddCommandRuns < ActiveRecord::Migration[8.2]
  def change
    create_table :command_runs do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :agent_task_run, null: false, foreign_key: true
      t.references :tool_invocation, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :lifecycle_state, null: false, default: "starting"
      t.string :command_line, null: false
      t.integer :timeout_seconds
      t.boolean :pty, null: false, default: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :exit_status
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :command_runs, :public_id, unique: true
    remove_index :command_runs, :tool_invocation_id
    add_index :command_runs, :tool_invocation_id, unique: true
    add_index :tool_invocations, [:tool_binding_id, :idempotency_key], unique: true, where: "idempotency_key IS NOT NULL", name: "idx_tool_invocations_binding_idempotency"
  end
end
