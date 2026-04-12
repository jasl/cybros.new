class CreateConversationControlRequests < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_control_requests do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :workspace, foreign_key: true
      t.references :agent, foreign_key: true
      t.references :conversation_supervision_session, null: false, foreign_key: true
      t.references :target_conversation, null: false, foreign_key: { to_table: :conversations }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :request_kind, null: false
      t.string :target_kind, null: false
      t.string :target_public_id
      t.string :lifecycle_state, null: false, default: "queued"
      t.jsonb :request_payload, null: false, default: {}
      t.jsonb :result_payload, null: false, default: {}
      t.datetime :completed_at
      t.timestamps
    end

    add_index :conversation_control_requests, :public_id, unique: true
    add_index :conversation_control_requests,
              [:installation_id, :request_kind, :lifecycle_state, :target_conversation_id, :completed_at],
              name: "idx_ccr_guidance_projection_conversation"
    add_index :conversation_control_requests,
              [:installation_id, :request_kind, :lifecycle_state, :target_public_id, :completed_at],
              name: "idx_ccr_guidance_projection_subagent"
  end
end
