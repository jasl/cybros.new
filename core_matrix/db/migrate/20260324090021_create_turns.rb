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
      t.references :user, foreign_key: true
      t.references :workspace, foreign_key: true
      t.references :agent, foreign_key: true
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
      t.bigint :selected_input_message_id
      t.bigint :selected_output_message_id
      t.datetime :cancellation_requested_at
      t.string :cancellation_reason_kind
      t.integer :agent_config_version, null: false, default: 1
      t.string :agent_config_content_fingerprint, null: false
      t.jsonb :feature_policy_snapshot, null: false, default: {}
      t.jsonb :resolved_config_snapshot, null: false, default: {}
      t.jsonb :resolved_model_selection_snapshot, null: false, default: {}
      t.string :workflow_bootstrap_state, null: false, default: "not_requested"
      t.jsonb :workflow_bootstrap_payload, null: false, default: {}
      t.jsonb :workflow_bootstrap_failure_payload, null: false, default: {}
      t.datetime :workflow_bootstrap_requested_at
      t.datetime :workflow_bootstrap_started_at
      t.datetime :workflow_bootstrap_finished_at

      t.timestamps
    end

    add_foreign_key :conversations, :conversation_execution_epochs, column: :current_execution_epoch_id
    add_foreign_key :conversations, :turns, column: :latest_active_turn_id
    add_foreign_key :conversations, :turns, column: :latest_turn_id
    execute <<~SQL
      ALTER TABLE conversation_execution_epochs
      ADD COLUMN execution_runtime_alignment_id bigint
      GENERATED ALWAYS AS (COALESCE(execution_runtime_id, 0)) STORED
    SQL
    execute <<~SQL
      ALTER TABLE conversations
      ADD COLUMN current_execution_runtime_alignment_id bigint
      GENERATED ALWAYS AS (COALESCE(current_execution_runtime_id, 0)) STORED
    SQL
    add_index :conversation_execution_epochs, :public_id, unique: true
    add_index :conversation_execution_epochs, [:conversation_id, :sequence], unique: true
    add_index :conversation_execution_epochs,
              :conversation_id,
              unique: true,
              where: "lifecycle_state = 'active'",
              name: "idx_conversation_execution_epochs_active"
    add_index :conversation_execution_epochs,
              [:id, :execution_runtime_alignment_id],
              unique: true,
              name: "idx_conversation_execution_epochs_runtime_alignment"
    add_index :turns, [:conversation_id, :sequence], unique: true
    add_index :turns, :public_id, unique: true
    add_index :turns,
              [:workflow_bootstrap_state, :workflow_bootstrap_started_at],
              name: "idx_turns_workflow_bootstrap_backlog"
    add_check_constraint :turns,
                         "((cancellation_reason_kind IS NULL AND cancellation_requested_at IS NULL) OR (cancellation_reason_kind IS NOT NULL AND cancellation_requested_at IS NOT NULL))",
                         name: "chk_turns_cancellation_pairing"
    add_check_constraint :turns,
                         "workflow_bootstrap_state IN ('not_requested', 'pending', 'materializing', 'ready', 'failed')",
                         name: "chk_turns_workflow_bootstrap_state"
    add_check_constraint :turns,
                         <<~SQL.squish,
                           (
                             (workflow_bootstrap_state = 'not_requested' AND workflow_bootstrap_payload = '{}'::jsonb)
                             OR
                             (
                               workflow_bootstrap_state IN ('pending', 'materializing', 'ready', 'failed')
                               AND jsonb_typeof(workflow_bootstrap_payload) = 'object'
                               AND workflow_bootstrap_payload ?& ARRAY['selector_source', 'selector', 'root_node_key', 'root_node_type', 'decision_source', 'metadata']
                               AND (workflow_bootstrap_payload - ARRAY['selector_source', 'selector', 'root_node_key', 'root_node_type', 'decision_source', 'metadata']::text[]) = '{}'::jsonb
                               AND jsonb_typeof(workflow_bootstrap_payload->'metadata') = 'object'
                             )
                           )
                         SQL
                         name: "chk_turns_workflow_bootstrap_payload_contract"
    add_check_constraint :turns,
                         <<~SQL.squish,
                           (
                             (
                               workflow_bootstrap_state IN ('not_requested', 'pending', 'materializing', 'ready')
                               AND workflow_bootstrap_failure_payload = '{}'::jsonb
                             )
                             OR
                             (
                               workflow_bootstrap_state = 'failed'
                               AND jsonb_typeof(workflow_bootstrap_failure_payload) = 'object'
                               AND workflow_bootstrap_failure_payload ?& ARRAY['error_class', 'error_message', 'retryable']
                               AND (workflow_bootstrap_failure_payload - ARRAY['error_class', 'error_message', 'retryable']::text[]) = '{}'::jsonb
                               AND jsonb_typeof(workflow_bootstrap_failure_payload->'retryable') = 'boolean'
                             )
                           )
                         SQL
                         name: "chk_turns_workflow_bootstrap_failure_contract"
    add_check_constraint :turns,
                         <<~SQL.squish,
                           (
                             (
                               workflow_bootstrap_state = 'not_requested'
                               AND workflow_bootstrap_requested_at IS NULL
                               AND workflow_bootstrap_started_at IS NULL
                               AND workflow_bootstrap_finished_at IS NULL
                             )
                             OR
                             (
                               workflow_bootstrap_state = 'pending'
                               AND workflow_bootstrap_requested_at IS NOT NULL
                               AND workflow_bootstrap_started_at IS NULL
                               AND workflow_bootstrap_finished_at IS NULL
                             )
                             OR
                             (
                               workflow_bootstrap_state = 'materializing'
                               AND workflow_bootstrap_requested_at IS NOT NULL
                               AND workflow_bootstrap_started_at IS NOT NULL
                               AND workflow_bootstrap_finished_at IS NULL
                             )
                             OR
                             (
                               workflow_bootstrap_state IN ('ready', 'failed')
                               AND workflow_bootstrap_requested_at IS NOT NULL
                               AND workflow_bootstrap_started_at IS NOT NULL
                               AND workflow_bootstrap_finished_at IS NOT NULL
                             )
                           )
                         SQL
                         name: "chk_turns_workflow_bootstrap_timestamps"

    change_table :conversations, bulk: true do |t|
      t.string :interactive_selector_mode, null: false, default: "auto"
      t.string :interactive_selector_provider_handle
      t.string :interactive_selector_model_ref
      t.string :override_last_schema_fingerprint
      t.datetime :override_updated_at
    end

    add_index :conversations,
              [:current_execution_epoch_id, :current_execution_runtime_alignment_id],
              name: "idx_conversations_current_execution_context_alignment"
    execute <<~SQL
      ALTER TABLE conversations
      ADD CONSTRAINT fk_conversations_current_execution_context_alignment
      FOREIGN KEY (current_execution_epoch_id, current_execution_runtime_alignment_id)
      REFERENCES conversation_execution_epochs(id, execution_runtime_alignment_id)
    SQL
  end
end
