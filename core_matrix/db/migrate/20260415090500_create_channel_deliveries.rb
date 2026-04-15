class CreateChannelDeliveries < ActiveRecord::Migration[8.2]
  def change
    create_table :channel_deliveries do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :ingress_binding, null: false, foreign_key: true
      t.references :channel_connector, null: false, foreign_key: true
      t.references :channel_session, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :turn, foreign_key: true
      t.references :message, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :external_message_key, null: false
      t.string :reply_to_external_message_key
      t.string :delivery_state, null: false, default: "queued"
      t.jsonb :payload, null: false, default: {}
      t.datetime :delivered_at
      t.datetime :failed_at
      t.jsonb :failure_payload, null: false, default: {}

      t.timestamps
    end

    add_index :channel_deliveries, :public_id, unique: true
    add_index :channel_deliveries, :external_message_key
    add_index :channel_deliveries, [:channel_session_id, :created_at], name: "idx_channel_deliveries_session_created"
  end
end
