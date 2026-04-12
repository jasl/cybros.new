class AddCommandRuns < ActiveRecord::Migration[8.2]
  def change
    create_table :command_runs do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :tool_invocation, null: false, foreign_key: true, index: false
      t.references :agent_task_run, foreign_key: true
      t.references :workflow_node, foreign_key: true
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
    add_index :command_runs, :tool_invocation_id, unique: true
    add_index :tool_invocations, [:workflow_node_id, :idempotency_key], unique: true,
              where: "workflow_node_id IS NOT NULL AND idempotency_key IS NOT NULL",
              name: "idx_tool_invocations_workflow_node_idempotency"
    add_index :tool_invocations, [:agent_task_run_id, :idempotency_key], unique: true,
              where: "workflow_node_id IS NULL AND agent_task_run_id IS NOT NULL AND idempotency_key IS NOT NULL",
              name: "idx_tool_invocations_agent_task_idempotency"
  end
end
