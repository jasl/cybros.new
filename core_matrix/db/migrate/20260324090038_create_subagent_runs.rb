class CreateSubagentRuns < ActiveRecord::Migration[8.2]
  def change
    create_table :subagent_runs do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workflow_run, null: false, foreign_key: true
      t.references :workflow_node, null: false, foreign_key: true
      t.references :parent_subagent_run, foreign_key: { to_table: :subagent_runs }
      t.references :terminal_summary_artifact, foreign_key: { to_table: :workflow_artifacts }
      t.string :lifecycle_state, null: false, default: "running"
      t.integer :depth, null: false, default: 0
      t.string :batch_key
      t.string :coordination_key
      t.string :requested_role_or_slot, null: false
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.string :failure_reason
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :subagent_runs, [:workflow_node_id, :created_at], name: "idx_subagent_runs_node_created"
    add_index :subagent_runs, [:workflow_run_id, :batch_key], name: "idx_subagent_runs_run_batch"
    add_index :subagent_runs, [:workflow_run_id, :coordination_key], name: "idx_subagent_runs_run_coordination"
  end
end
