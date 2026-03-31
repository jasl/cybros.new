class AddWaitStateToWorkflowRuns < ActiveRecord::Migration[8.2]
  def change
    change_table :workflow_runs, bulk: true do |t|
      t.string :wait_state, null: false, default: "ready"
      t.string :wait_reason_kind
      t.jsonb :wait_reason_payload, null: false, default: {}
      t.datetime :waiting_since_at
      t.string :blocking_resource_type
      t.string :blocking_resource_id
    end
  end
end
