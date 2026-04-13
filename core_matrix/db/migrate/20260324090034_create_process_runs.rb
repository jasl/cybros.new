class CreateProcessRuns < ActiveRecord::Migration[8.2]
  def change
    create_table :process_runs do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :workspace, foreign_key: true
      t.references :agent, foreign_key: true
      t.references :workflow_node, null: false, foreign_key: true
      t.references :workflow_run, null: false, foreign_key: true
      t.references :execution_epoch, null: false, foreign_key: { to_table: :conversation_execution_epochs }
      t.references :execution_runtime, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :turn, null: false, foreign_key: true
      t.references :origin_message, foreign_key: { to_table: :messages }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :idempotency_key
      t.string :kind, null: false
      t.string :lifecycle_state, null: false, default: "running"
      t.string :command_line, null: false
      t.integer :timeout_seconds
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :exit_status
      t.jsonb :metadata, null: false, default: {}
      t.string :close_state, null: false, default: "open"
      t.string :close_reason_kind
      t.datetime :close_requested_at
      t.datetime :close_grace_deadline_at
      t.datetime :close_force_deadline_at
      t.datetime :close_acknowledged_at
      t.string :close_outcome_kind
      t.jsonb :close_outcome_payload, null: false, default: {}

      t.timestamps
    end

    add_index :process_runs, :public_id, unique: true
    add_index :process_runs, [:workflow_node_id, :idempotency_key], unique: true,
              where: "idempotency_key IS NOT NULL",
              name: "idx_process_runs_workflow_node_idempotency"
    add_index :process_runs, [:workflow_node_id, :lifecycle_state]
    add_index :process_runs, [:workflow_run_id, :lifecycle_state], name: "idx_process_runs_workflow_run_lifecycle"
    add_index :process_runs, [:execution_runtime_id, :lifecycle_state], name: "idx_process_runs_executor_lifecycle"
    add_index :process_runs, [:conversation_id, :lifecycle_state], name: "idx_process_runs_conversation_lifecycle"
    add_foreign_key :process_runs, :workflow_nodes,
                    column: [:workflow_node_id, :workflow_run_id],
                    primary_key: [:id, :workflow_run_id],
                    name: "fk_process_runs_workflow_node_workflow_run"
  end
end
