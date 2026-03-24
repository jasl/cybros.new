class AddWaitStateToWorkflowRuns < ActiveRecord::Migration[8.2]
  def change
    add_column :workflow_runs, :wait_state, :string, null: false, default: "ready"
    add_column :workflow_runs, :wait_reason_kind, :string
    add_column :workflow_runs, :wait_reason_payload, :jsonb, null: false, default: {}
    add_column :workflow_runs, :waiting_since_at, :datetime
    add_column :workflow_runs, :blocking_resource_type, :string
    add_column :workflow_runs, :blocking_resource_id, :string
  end
end
