class AddExecutionContextAlignmentAndWorkflowBootstrapConstraints < ActiveRecord::Migration[8.2]
  def up
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
    add_index :conversation_execution_epochs,
      [:id, :execution_runtime_alignment_id],
      unique: true,
      name: "idx_conversation_execution_epochs_runtime_alignment"
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

  def down
    execute "ALTER TABLE conversations DROP CONSTRAINT IF EXISTS fk_conversations_current_execution_context_alignment"
    remove_index :conversations, name: "idx_conversations_current_execution_context_alignment", if_exists: true
    remove_index :conversation_execution_epochs, name: "idx_conversation_execution_epochs_runtime_alignment", if_exists: true
    execute "ALTER TABLE conversations DROP COLUMN IF EXISTS current_execution_runtime_alignment_id"
    execute "ALTER TABLE conversation_execution_epochs DROP COLUMN IF EXISTS execution_runtime_alignment_id"

    remove_check_constraint :turns, name: "chk_turns_workflow_bootstrap_timestamps"
    remove_check_constraint :turns, name: "chk_turns_workflow_bootstrap_failure_contract"
    remove_check_constraint :turns, name: "chk_turns_workflow_bootstrap_payload_contract"
    remove_check_constraint :turns, name: "chk_turns_workflow_bootstrap_state"
  end
end
