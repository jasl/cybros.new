class CreateConversationObservationFrames < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_supervision_snapshots do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :target_conversation, null: false, foreign_key: { to_table: :conversations }
      t.references :conversation_supervision_session, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :conversation_supervision_state_public_id
      t.string :conversation_capability_policy_public_id
      t.string :anchor_turn_public_id
      t.integer :anchor_turn_sequence_snapshot
      t.integer :conversation_event_projection_sequence_snapshot
      t.string :active_workflow_run_public_id
      t.string :active_workflow_node_public_id
      t.jsonb :active_subagent_connection_public_ids, null: false, default: []
      t.jsonb :bundle_payload, null: false, default: {}
      t.jsonb :machine_status_payload, null: false, default: {}

      t.timestamps
    end

    add_index :conversation_supervision_snapshots, :public_id, unique: true
    add_index :conversation_supervision_snapshots,
      [:conversation_supervision_session_id, :created_at],
      name: "idx_conversation_supervision_snapshots_session_created"
  end
end
