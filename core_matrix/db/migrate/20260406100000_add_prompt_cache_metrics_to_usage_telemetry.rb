class AddPromptCacheMetricsToUsageTelemetry < ActiveRecord::Migration[8.2]
  def change
    add_column :usage_events, :prompt_cache_status, :string, null: false, default: "unknown"
    add_column :usage_events, :cached_input_tokens, :integer

    add_column :usage_rollups, :cached_input_tokens_total, :integer, null: false, default: 0
    add_column :usage_rollups, :prompt_cache_available_event_count, :integer, null: false, default: 0
    add_column :usage_rollups, :prompt_cache_unknown_event_count, :integer, null: false, default: 0
    add_column :usage_rollups, :prompt_cache_unsupported_event_count, :integer, null: false, default: 0

    add_column :turn_diagnostics_snapshots, :cached_input_tokens_total, :integer, null: false, default: 0
    add_column :turn_diagnostics_snapshots, :prompt_cache_available_event_count, :integer, null: false, default: 0
    add_column :turn_diagnostics_snapshots, :prompt_cache_unknown_event_count, :integer, null: false, default: 0
    add_column :turn_diagnostics_snapshots, :prompt_cache_unsupported_event_count, :integer, null: false, default: 0

    add_column :conversation_diagnostics_snapshots, :cached_input_tokens_total, :integer, null: false, default: 0
    add_column :conversation_diagnostics_snapshots, :prompt_cache_available_event_count, :integer, null: false, default: 0
    add_column :conversation_diagnostics_snapshots, :prompt_cache_unknown_event_count, :integer, null: false, default: 0
    add_column :conversation_diagnostics_snapshots, :prompt_cache_unsupported_event_count, :integer, null: false, default: 0
  end
end
