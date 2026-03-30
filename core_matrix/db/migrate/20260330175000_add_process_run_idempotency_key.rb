class AddProcessRunIdempotencyKey < ActiveRecord::Migration[8.2]
  def change
    add_column :process_runs, :idempotency_key, :string
    add_index :process_runs, [:workflow_node_id, :idempotency_key], unique: true, where: "idempotency_key IS NOT NULL", name: "idx_process_runs_workflow_node_idempotency"
  end
end
