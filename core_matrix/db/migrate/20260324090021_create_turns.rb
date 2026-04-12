class CreateTurns < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_execution_epochs do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :execution_runtime, foreign_key: true
      t.references :source_execution_epoch, foreign_key: { to_table: :conversation_execution_epochs }
      t.integer :sequence, null: false
      t.string :lifecycle_state, null: false, default: "active"
      t.jsonb :continuity_payload, null: false, default: {}
      t.datetime :opened_at, null: false
      t.datetime :closed_at
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }

      t.timestamps
    end

    create_table :turns do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :agent_definition_version, null: false, foreign_key: true
      t.references :execution_epoch, null: false, foreign_key: { to_table: :conversation_execution_epochs }
      t.references :execution_runtime, foreign_key: true
      t.references :execution_runtime_version, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.integer :sequence, null: false
      t.string :lifecycle_state, null: false
      t.string :origin_kind, null: false
      t.jsonb :origin_payload, null: false, default: {}
      t.string :source_ref_type
      t.string :source_ref_id
      t.string :idempotency_key
      t.string :external_event_key
      t.datetime :cancellation_requested_at
      t.string :cancellation_reason_kind
      t.integer :agent_config_version, null: false, default: 1
      t.string :agent_config_content_fingerprint, null: false
      t.jsonb :resolved_config_snapshot, null: false, default: {}
      t.jsonb :resolved_model_selection_snapshot, null: false, default: {}

      t.timestamps
    end

    add_foreign_key :conversations, :conversation_execution_epochs, column: :current_execution_epoch_id
    add_index :conversation_execution_epochs, :public_id, unique: true
    add_index :conversation_execution_epochs, [:conversation_id, :sequence], unique: true
    add_index :conversation_execution_epochs,
              :conversation_id,
              unique: true,
              where: "lifecycle_state = 'active'",
              name: "idx_conversation_execution_epochs_active"
    add_index :turns, [:conversation_id, :sequence], unique: true
    add_index :turns, :public_id, unique: true
    add_check_constraint :turns,
                         "cancellation_reason_kind IS NULL OR (cancellation_reason_kind::text = ANY (ARRAY['conversation_deleted'::character varying::text, 'conversation_archived'::character varying::text, 'turn_interrupted'::character varying::text]))",
                         name: "chk_turns_cancellation_reason_kind"
    add_check_constraint :turns,
                         "((cancellation_reason_kind IS NULL AND cancellation_requested_at IS NULL) OR (cancellation_reason_kind IS NOT NULL AND cancellation_requested_at IS NOT NULL))",
                         name: "chk_turns_cancellation_pairing"

    change_table :conversations, bulk: true do |t|
      t.string :interactive_selector_mode, null: false, default: "auto"
      t.string :interactive_selector_provider_handle
      t.string :interactive_selector_model_ref
      t.jsonb :override_payload, null: false, default: {}
      t.string :override_last_schema_fingerprint
      t.jsonb :override_reconciliation_report, null: false, default: {}
      t.datetime :override_updated_at
    end
  end
end
