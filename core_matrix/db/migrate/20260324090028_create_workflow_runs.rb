class CreateWorkflowRuns < ActiveRecord::Migration[8.2]
  def change
    create_table :workflow_runs do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :workspace, foreign_key: true
      t.references :agent, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :turn, null: false, foreign_key: true, index: { unique: true }
      t.references :execution_runtime, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :lifecycle_state, null: false, default: "active"
      t.datetime :cancellation_requested_at
      t.string :cancellation_reason_kind

      t.timestamps
    end

    add_index :workflow_runs, :public_id, unique: true
    add_foreign_key :conversations, :workflow_runs, column: :latest_active_workflow_run_id
    add_foreign_key :execution_profile_facts, :workflow_runs, column: :workflow_run_id
    add_index :workflow_runs,
      :conversation_id,
      unique: true,
      where: "((lifecycle_state)::text = 'active'::text)",
      name: "index_workflow_runs_on_conversation_id_active"
    add_check_constraint :workflow_runs,
                         "((cancellation_reason_kind IS NULL AND cancellation_requested_at IS NULL) OR (cancellation_reason_kind IS NOT NULL AND cancellation_requested_at IS NOT NULL))",
                         name: "chk_workflow_runs_cancellation_pairing"
  end
end
