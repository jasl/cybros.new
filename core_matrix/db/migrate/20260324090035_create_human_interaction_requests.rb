class CreateHumanInteractionRequests < ActiveRecord::Migration[8.2]
  def change
    create_table :human_interaction_requests do |t|
      t.string :type, null: false
      t.references :installation, null: false, foreign_key: true
      t.references :workflow_run, null: false, foreign_key: true
      t.references :workflow_node, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :turn, null: false, foreign_key: true
      t.string :lifecycle_state, null: false, default: "open"
      t.string :resolution_kind
      t.boolean :blocking, null: false, default: true
      t.jsonb :request_payload, null: false, default: {}
      t.jsonb :result_payload, null: false, default: {}
      t.datetime :expires_at
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :human_interaction_requests, [:conversation_id, :lifecycle_state], name: "idx_human_requests_conversation_lifecycle"
    add_index :human_interaction_requests, [:workflow_run_id, :lifecycle_state], name: "idx_human_requests_workflow_lifecycle"
    add_index :human_interaction_requests, [:type, :lifecycle_state], name: "idx_human_requests_type_lifecycle"
  end
end
