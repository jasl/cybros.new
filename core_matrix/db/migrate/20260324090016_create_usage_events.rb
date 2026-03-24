class CreateUsageEvents < ActiveRecord::Migration[8.2]
  def change
    create_table :usage_events do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :workspace, foreign_key: true
      t.bigint :conversation_id
      t.bigint :turn_id
      t.string :workflow_node_key
      t.references :agent_installation, foreign_key: true
      t.references :agent_deployment, foreign_key: true
      t.string :provider_handle, null: false
      t.string :model_ref, null: false
      t.string :operation_kind, null: false
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :media_units
      t.integer :latency_ms
      t.decimal :estimated_cost, precision: 12, scale: 6
      t.boolean :success, null: false
      t.string :entitlement_window_key
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :usage_events, [:installation_id, :occurred_at]
    add_index :usage_events, [:provider_handle, :model_ref]
  end
end
