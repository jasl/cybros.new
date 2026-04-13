class AddWorkflowRunRedundancyToProcessRuns < ActiveRecord::Migration[8.2]
  def up
    add_reference :process_runs, :workflow_run, foreign_key: true
    add_index :workflow_nodes, [:id, :workflow_run_id], unique: true, name: "idx_workflow_nodes_run_alignment"

    execute <<~SQL
      UPDATE process_runs
      SET workflow_run_id = workflow_nodes.workflow_run_id
      FROM workflow_nodes
      WHERE workflow_nodes.id = process_runs.workflow_node_id
    SQL

    change_column_null :process_runs, :workflow_run_id, false
    add_index :process_runs, [:workflow_run_id, :lifecycle_state], name: "idx_process_runs_workflow_run_lifecycle"
    add_foreign_key :process_runs, :workflow_nodes,
      column: [:workflow_node_id, :workflow_run_id],
      primary_key: [:id, :workflow_run_id],
      name: "fk_process_runs_workflow_node_workflow_run"
  end

  def down
    remove_foreign_key :process_runs, name: "fk_process_runs_workflow_node_workflow_run"
    remove_index :process_runs, name: "idx_process_runs_workflow_run_lifecycle"
    remove_column :process_runs, :workflow_run_id
    remove_index :workflow_nodes, name: "idx_workflow_nodes_run_alignment"
  end
end
