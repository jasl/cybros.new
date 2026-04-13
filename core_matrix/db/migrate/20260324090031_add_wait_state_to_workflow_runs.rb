class AddWaitStateToWorkflowRuns < ActiveRecord::Migration[8.2]
  def change
    change_table :workflow_runs, bulk: true do |t|
      t.string :wait_state, null: false, default: "ready"
      t.string :wait_reason_kind
      t.string :wait_policy_mode
      t.string :wait_retry_scope
      t.string :wait_resume_mode
      t.string :wait_failure_kind
      t.string :wait_retry_strategy
      t.integer :wait_attempt_no
      t.integer :wait_max_auto_retries
      t.datetime :wait_next_retry_at
      t.text :wait_last_error_summary
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
