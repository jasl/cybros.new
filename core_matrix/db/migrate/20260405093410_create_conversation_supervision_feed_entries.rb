class CreateConversationSupervisionFeedEntries < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_supervision_feed_entries do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :workspace, foreign_key: true
      t.references :agent, foreign_key: true
      t.references :target_conversation,
        null: false,
        foreign_key: { to_table: :conversations }
      t.references :target_turn, foreign_key: { to_table: :turns }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.integer :sequence, null: false
      t.string :event_kind, null: false
      t.string :summary, null: false
      t.jsonb :details_payload, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :conversation_supervision_feed_entries, :public_id, unique: true
    add_index :conversation_supervision_feed_entries,
      [:installation_id, :user_id, :occurred_at],
      name: "idx_conversation_supervision_feed_entries_user_occurred"
    add_index :conversation_supervision_feed_entries,
      [:target_conversation_id, :sequence],
      unique: true,
      name: "idx_conversation_supervision_feed_entries_sequence"
    add_index :conversation_supervision_feed_entries,
      [:target_conversation_id, :target_turn_id, :sequence],
      name: "idx_conversation_supervision_feed_entries_turn_sequence"
  end
end
