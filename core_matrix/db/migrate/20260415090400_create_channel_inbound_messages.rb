class CreateChannelInboundMessages < ActiveRecord::Migration[8.2]
  def change
    create_table :channel_inbound_messages do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :ingress_binding, null: false, foreign_key: true
      t.references :channel_connector, null: false, foreign_key: true
      t.references :channel_session, null: false, foreign_key: true
      t.references :conversation, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :external_event_key, null: false
      t.string :external_message_key, null: false
      t.string :external_sender_id, null: false
      t.jsonb :sender_snapshot, null: false, default: {}
      t.jsonb :content, null: false, default: {}
      t.jsonb :normalized_payload, null: false, default: {}
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :received_at, null: false

      t.timestamps
    end

    add_index :channel_inbound_messages, :public_id, unique: true
    add_index :channel_inbound_messages,
      [:channel_connector_id, :external_event_key],
      unique: true,
      name: "idx_channel_inbound_messages_event_key"
    add_index :channel_inbound_messages, :external_message_key
  end
end
