class CreateExecutionProfileFacts < ActiveRecord::Migration[8.2]
  def change
    create_table :execution_profile_facts do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :workspace, foreign_key: true
      t.bigint :conversation_id
      t.bigint :turn_id
      t.string :workflow_node_key
      t.bigint :process_run_id
      t.bigint :subagent_connection_id
      t.bigint :human_interaction_request_id
      t.string :fact_kind, null: false
      t.string :fact_key, null: false
      t.string :provider_request_id
      t.string :provider_handle
      t.string :model_ref
      t.string :api_model
      t.string :wire_api
      t.integer :total_tokens
      t.integer :recommended_compaction_threshold
      t.boolean :threshold_crossed
      t.string :error_class
      t.text :error_message
      t.integer :count_value
      t.integer :duration_ms
      t.boolean :success
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :execution_profile_facts, [:installation_id, :occurred_at]
    add_index :execution_profile_facts, [:installation_id, :fact_kind, :fact_key], name: "idx_execution_profile_facts_installation_kind_key"
  end
end
