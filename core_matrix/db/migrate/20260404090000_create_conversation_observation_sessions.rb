class CreateConversationObservationSessions < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_observation_sessions do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :target_conversation, null: false, foreign_key: { to_table: :conversations }
      t.references :initiator, null: false, polymorphic: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :lifecycle_state, null: false, default: "open"
      t.string :responder_strategy, null: false, default: "builtin"
      t.jsonb :capability_policy_snapshot, null: false, default: {}

      t.datetime :last_observed_at
      t.timestamps
    end

    add_index :conversation_observation_sessions, :public_id, unique: true
    add_index :conversation_observation_sessions,
      [:target_conversation_id, :created_at],
      name: "idx_conversation_observation_sessions_target_created"
  end
end
