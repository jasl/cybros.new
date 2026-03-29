class AddConversationCloseOperationsAndInterruptEnums < ActiveRecord::Migration[8.2]
  def up
    create_table :conversation_close_operations do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :intent_kind, null: false
      t.string :lifecycle_state, null: false, default: "requested"
      t.jsonb :summary_payload, null: false, default: {}
      t.datetime :requested_at, null: false
      t.datetime :completed_at
      t.timestamps
    end

    add_index :conversation_close_operations, :public_id, unique: true
    add_index :conversation_close_operations,
      :conversation_id,
      unique: true,
      where: "lifecycle_state NOT IN ('completed', 'degraded')",
      name: "idx_conversation_close_operations_unfinished"

    remove_check_constraint :turns, name: "chk_turns_cancellation_reason_kind"
    add_check_constraint :turns,
      "cancellation_reason_kind IS NULL OR (cancellation_reason_kind::text = ANY (ARRAY['conversation_deleted'::character varying::text, 'conversation_archived'::character varying::text, 'turn_interrupted'::character varying::text]))",
      name: "chk_turns_cancellation_reason_kind"

    remove_check_constraint :workflow_runs, name: "chk_workflow_runs_cancellation_reason_kind"
    add_check_constraint :workflow_runs,
      "cancellation_reason_kind IS NULL OR (cancellation_reason_kind::text = ANY (ARRAY['conversation_deleted'::character varying::text, 'conversation_archived'::character varying::text, 'turn_interrupted'::character varying::text]))",
      name: "chk_workflow_runs_cancellation_reason_kind"
  end

  def down
    remove_check_constraint :workflow_runs, name: "chk_workflow_runs_cancellation_reason_kind"
    add_check_constraint :workflow_runs,
      "cancellation_reason_kind IS NULL OR (cancellation_reason_kind::text = ANY (ARRAY['conversation_deleted'::character varying::text, 'conversation_archived'::character varying::text]))",
      name: "chk_workflow_runs_cancellation_reason_kind"

    remove_check_constraint :turns, name: "chk_turns_cancellation_reason_kind"
    add_check_constraint :turns,
      "cancellation_reason_kind IS NULL OR (cancellation_reason_kind::text = ANY (ARRAY['conversation_deleted'::character varying::text, 'conversation_archived'::character varying::text]))",
      name: "chk_turns_cancellation_reason_kind"

    drop_table :conversation_close_operations
  end
end
