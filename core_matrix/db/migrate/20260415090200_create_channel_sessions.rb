class CreateChannelSessions < ActiveRecord::Migration[8.2]
  def change
    create_table :channel_sessions do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :ingress_binding, null: false, foreign_key: true
      t.references :channel_connector, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :platform, null: false
      t.string :peer_kind, null: false
      t.string :peer_id, null: false
      t.string :thread_key
      t.string :normalized_thread_key, null: false, default: ""
      t.string :binding_state, null: false, default: "active"
      t.datetime :last_inbound_at
      t.datetime :last_outbound_at
      t.jsonb :session_metadata, null: false, default: {}

      t.timestamps
    end

    add_index :channel_sessions, :public_id, unique: true
    add_index :channel_sessions,
      [:channel_connector_id, :peer_kind, :peer_id, :normalized_thread_key],
      unique: true,
      name: "idx_channel_sessions_boundary"
  end
end
