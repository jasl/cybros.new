class AddWaitStateToWorkflowRuns < ActiveRecord::Migration[8.2]
  def change
    change_table :workflow_runs, bulk: true do |t|
      t.string :wait_state, null: false, default: "ready"
      t.string :wait_reason_kind
      t.jsonb :wait_reason_payload, null: false, default: {}
      t.string :recovery_state
      t.string :recovery_reason
      t.string :recovery_drift_reason
      t.string :recovery_agent_task_run_public_id
      t.datetime :waiting_since_at
      t.string :blocking_resource_type
      t.string :blocking_resource_id
      t.references :wait_snapshot_document, foreign_key: { to_table: :json_documents }
    end
  end
end
