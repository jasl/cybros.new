class CreateWorkflowRuns < ActiveRecord::Migration[8.2]
  def change
    create_table :workflow_runs do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :turn, null: false, foreign_key: true, index: { unique: true }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :lifecycle_state, null: false, default: "active"
      t.datetime :cancellation_requested_at
      t.string :cancellation_reason_kind

      t.timestamps
    end

    add_index :workflow_runs, :public_id, unique: true
    add_index :workflow_runs,
      :conversation_id,
      unique: true,
      where: "((lifecycle_state)::text = 'active'::text)",
      name: "index_workflow_runs_on_conversation_id_active"
    add_check_constraint :workflow_runs,
                         "cancellation_reason_kind IS NULL OR (cancellation_reason_kind::text = ANY (ARRAY['conversation_deleted'::character varying::text, 'conversation_archived'::character varying::text, 'turn_interrupted'::character varying::text]))",
                         name: "chk_workflow_runs_cancellation_reason_kind"
    add_check_constraint :workflow_runs,
                         "((cancellation_reason_kind IS NULL AND cancellation_requested_at IS NULL) OR (cancellation_reason_kind IS NOT NULL AND cancellation_requested_at IS NOT NULL))",
                         name: "chk_workflow_runs_cancellation_pairing"
  end
end
