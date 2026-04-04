class CreateConversationObservationFrames < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_observation_frames do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :target_conversation, null: false, foreign_key: { to_table: :conversations }
      t.references :conversation_observation_session, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :anchor_turn_public_id
      t.integer :anchor_turn_sequence_snapshot
      t.integer :conversation_event_projection_sequence_snapshot
      t.string :active_workflow_run_public_id
      t.string :active_workflow_node_public_id
      t.string :wait_state
      t.string :wait_reason_kind
      t.jsonb :active_subagent_session_public_ids, null: false, default: []
      t.jsonb :bundle_snapshot, null: false, default: {}
      t.jsonb :runtime_state_snapshot, null: false, default: {}
      t.jsonb :assessment_payload, null: false, default: {}

      t.timestamps
    end

    add_index :conversation_observation_frames, :public_id, unique: true
    add_index :conversation_observation_frames,
      [:conversation_observation_session_id, :created_at],
      name: "idx_conversation_observation_frames_session_created"
  end
end
