class CreateConversationDiagnosticsSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :turn_diagnostics_snapshots do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :turn, null: false, foreign_key: true, index: { unique: true }
      t.string :lifecycle_state, null: false
      t.integer :usage_event_count, null: false, default: 0
      t.integer :input_tokens_total, null: false, default: 0
      t.integer :output_tokens_total, null: false, default: 0
      t.integer :cached_input_tokens_total, null: false, default: 0
      t.decimal :estimated_cost_total, null: false, default: 0, precision: 12, scale: 6
      t.integer :attributed_user_usage_event_count, null: false, default: 0
      t.integer :attributed_user_input_tokens_total, null: false, default: 0
      t.integer :attributed_user_output_tokens_total, null: false, default: 0
      t.decimal :attributed_user_estimated_cost_total, null: false, default: 0, precision: 12, scale: 6
      t.integer :provider_round_count, null: false, default: 0
      t.integer :tool_call_count, null: false, default: 0
      t.integer :tool_failure_count, null: false, default: 0
      t.integer :command_run_count, null: false, default: 0
      t.integer :command_failure_count, null: false, default: 0
      t.integer :process_run_count, null: false, default: 0
      t.integer :process_failure_count, null: false, default: 0
      t.integer :subagent_connection_count, null: false, default: 0
      t.integer :input_variant_count, null: false, default: 0
      t.integer :output_variant_count, null: false, default: 0
      t.integer :resume_attempt_count, null: false, default: 0
      t.integer :retry_attempt_count, null: false, default: 0
      t.integer :avg_latency_ms, null: false, default: 0
      t.integer :max_latency_ms, null: false, default: 0
      t.integer :estimated_cost_event_count, null: false, default: 0
      t.integer :estimated_cost_missing_event_count, null: false, default: 0
      t.integer :attributed_user_estimated_cost_event_count, null: false, default: 0
      t.integer :attributed_user_estimated_cost_missing_event_count, null: false, default: 0
      t.integer :prompt_cache_available_event_count, null: false, default: 0
      t.integer :prompt_cache_unknown_event_count, null: false, default: 0
      t.integer :prompt_cache_unsupported_event_count, null: false, default: 0
      t.string :pause_state
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    create_table :conversation_diagnostics_snapshots do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true, index: { unique: true }
      t.string :lifecycle_state, null: false
      t.integer :turn_count, null: false, default: 0
      t.integer :active_turn_count, null: false, default: 0
      t.integer :completed_turn_count, null: false, default: 0
      t.integer :failed_turn_count, null: false, default: 0
      t.integer :canceled_turn_count, null: false, default: 0
      t.integer :usage_event_count, null: false, default: 0
      t.integer :input_tokens_total, null: false, default: 0
      t.integer :output_tokens_total, null: false, default: 0
      t.integer :cached_input_tokens_total, null: false, default: 0
      t.decimal :estimated_cost_total, null: false, default: 0, precision: 12, scale: 6
      t.integer :attributed_user_usage_event_count, null: false, default: 0
      t.integer :attributed_user_input_tokens_total, null: false, default: 0
      t.integer :attributed_user_output_tokens_total, null: false, default: 0
      t.decimal :attributed_user_estimated_cost_total, null: false, default: 0, precision: 12, scale: 6
      t.integer :provider_round_count, null: false, default: 0
      t.integer :tool_call_count, null: false, default: 0
      t.integer :tool_failure_count, null: false, default: 0
      t.integer :command_run_count, null: false, default: 0
      t.integer :command_failure_count, null: false, default: 0
      t.integer :process_run_count, null: false, default: 0
      t.integer :process_failure_count, null: false, default: 0
      t.integer :subagent_connection_count, null: false, default: 0
      t.integer :input_variant_count, null: false, default: 0
      t.integer :output_variant_count, null: false, default: 0
      t.integer :resume_attempt_count, null: false, default: 0
      t.integer :retry_attempt_count, null: false, default: 0
      t.integer :estimated_cost_event_count, null: false, default: 0
      t.integer :estimated_cost_missing_event_count, null: false, default: 0
      t.integer :attributed_user_estimated_cost_event_count, null: false, default: 0
      t.integer :attributed_user_estimated_cost_missing_event_count, null: false, default: 0
      t.integer :prompt_cache_available_event_count, null: false, default: 0
      t.integer :prompt_cache_unknown_event_count, null: false, default: 0
      t.integer :prompt_cache_unsupported_event_count, null: false, default: 0
      t.references :most_expensive_turn, foreign_key: { to_table: :turns }
      t.references :most_rounds_turn, foreign_key: { to_table: :turns }
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :usage_events, :conversation_id
    add_index :usage_events, :turn_id
  end
end
