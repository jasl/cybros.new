class CreateConversationEvents < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_events do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :turn, foreign_key: true
      t.string :source_type
      t.bigint :source_id
      t.integer :projection_sequence, null: false
      t.string :event_kind, null: false
      t.string :stream_key
      t.integer :stream_revision
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :conversation_events, [:conversation_id, :projection_sequence], unique: true, name: "idx_conversation_events_projection_sequence"
    add_index :conversation_events, [:source_type, :source_id], name: "idx_conversation_events_source"
    add_index :conversation_events,
      [:conversation_id, :stream_key, :stream_revision],
      unique: true,
      where: "stream_key IS NOT NULL",
      name: "idx_conversation_events_stream_revision"
  end
end
