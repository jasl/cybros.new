class CreateWorkflowNodes < ActiveRecord::Migration[8.2]
  def change
    create_table :workflow_nodes do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workflow_run, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :workspace, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :turn, foreign_key: true
      t.references :agent, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.integer :ordinal, null: false
      t.string :node_key, null: false
      t.string :node_type, null: false
      t.string :intent_id
      t.string :intent_batch_id
      t.string :intent_requirement
      t.string :intent_conflict_scope
      t.string :intent_idempotency_key
      t.string :lifecycle_state, null: false, default: "pending"
      t.datetime :started_at
      t.datetime :finished_at
      t.string :decision_source, null: false
      t.references :tool_call_document, foreign_key: { to_table: :json_documents }
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :workflow_nodes, [:workflow_run_id, :ordinal], unique: true
    add_index :workflow_nodes, [:workflow_run_id, :node_key], unique: true
    add_index :workflow_nodes,
      [:workflow_run_id, :lifecycle_state, :ordinal],
      name: "index_workflow_nodes_on_run_state_order"
    add_index :workflow_nodes, :public_id, unique: true
    add_check_constraint :workflow_nodes,
                         "(lifecycle_state IN ('pending', 'queued', 'running', 'waiting', 'completed', 'failed', 'canceled'))",
                         name: "chk_workflow_nodes_lifecycle_state"
  end
end
