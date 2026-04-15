class CreateChannelPairingRequests < ActiveRecord::Migration[8.2]
  def change
    create_table :channel_pairing_requests do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :ingress_binding, null: false, foreign_key: true
      t.references :channel_connector, null: false, foreign_key: true
      t.references :channel_session, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :platform_sender_id, null: false
      t.jsonb :sender_snapshot, null: false, default: {}
      t.string :pairing_code_digest, null: false
      t.string :lifecycle_state, null: false, default: "pending"
      t.datetime :expires_at, null: false
      t.datetime :approved_at
      t.datetime :rejected_at

      t.timestamps
    end

    add_index :channel_pairing_requests, :public_id, unique: true
    add_index :channel_pairing_requests,
      [:channel_connector_id, :platform_sender_id],
      unique: true,
      where: "lifecycle_state = 'pending'",
      name: "idx_channel_pairing_requests_pending_sender"
  end
end
