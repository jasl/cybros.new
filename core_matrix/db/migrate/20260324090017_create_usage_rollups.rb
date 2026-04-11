class CreateUsageRollups < ActiveRecord::Migration[8.2]
  def change
    create_table :usage_rollups do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :workspace, foreign_key: true
      t.bigint :conversation_id
      t.bigint :turn_id
      t.string :workflow_node_key
      t.references :agent, foreign_key: true
      t.references :agent_snapshot, foreign_key: true
      t.string :provider_handle, null: false
      t.string :model_ref, null: false
      t.string :operation_kind, null: false
      t.string :bucket_kind, null: false
      t.string :bucket_key, null: false
      t.string :dimension_digest, null: false
      t.integer :event_count, null: false, default: 0
      t.integer :success_count, null: false, default: 0
      t.integer :failure_count, null: false, default: 0
      t.integer :input_tokens_total, null: false, default: 0
      t.integer :cached_input_tokens_total, null: false, default: 0
      t.integer :output_tokens_total, null: false, default: 0
      t.integer :media_units_total, null: false, default: 0
      t.integer :total_latency_ms, null: false, default: 0
      t.decimal :estimated_cost_total, precision: 12, scale: 6, null: false, default: 0
      t.integer :prompt_cache_available_event_count, null: false, default: 0
      t.integer :prompt_cache_unknown_event_count, null: false, default: 0
      t.integer :prompt_cache_unsupported_event_count, null: false, default: 0

      t.timestamps
    end

    add_index :usage_rollups, [:installation_id, :bucket_kind, :bucket_key, :dimension_digest], unique: true, name: "idx_usage_rollups_installation_bucket_dimension"
  end
end
