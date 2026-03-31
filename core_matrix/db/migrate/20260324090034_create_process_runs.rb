class CreateProcessRuns < ActiveRecord::Migration[8.2]
  def change
    create_table :process_runs do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workflow_node, null: false, foreign_key: true
      t.references :execution_environment, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :turn, null: false, foreign_key: true
      t.references :origin_message, foreign_key: { to_table: :messages }
      t.string :idempotency_key
      t.string :kind, null: false
      t.string :lifecycle_state, null: false, default: "running"
      t.string :command_line, null: false
      t.integer :timeout_seconds
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :exit_status
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :process_runs, [:workflow_node_id, :idempotency_key], unique: true,
              where: "idempotency_key IS NOT NULL",
              name: "idx_process_runs_workflow_node_idempotency"
    add_index :process_runs, [:workflow_node_id, :lifecycle_state]
    add_index :process_runs, [:execution_environment_id, :lifecycle_state], name: "idx_process_runs_environment_lifecycle"
    add_index :process_runs, [:conversation_id, :lifecycle_state], name: "idx_process_runs_conversation_lifecycle"
  end
end
