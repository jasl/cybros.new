class CreateConversationObservationMessages < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_supervision_messages do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :workspace, foreign_key: true
      t.references :agent, foreign_key: true
      t.references :target_conversation, null: false, foreign_key: { to_table: :conversations }
      t.references :conversation_supervision_session, null: false, foreign_key: true
      t.references :conversation_supervision_snapshot, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :role, null: false
      t.text :content, null: false

      t.timestamps
    end

    add_index :conversation_supervision_messages, :public_id, unique: true
    add_index :conversation_supervision_messages,
      [:conversation_supervision_session_id, :created_at],
      name: "idx_conversation_supervision_messages_session_created"
  end
end
