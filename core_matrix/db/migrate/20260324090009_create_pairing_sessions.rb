class CreatePairingSessions < ActiveRecord::Migration[8.2]
  def change
    create_table :pairing_sessions do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.belongs_to :agent, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :token_digest, null: false
      t.datetime :issued_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :last_used_at
      t.datetime :runtime_registered_at
      t.datetime :agent_registered_at
      t.datetime :closed_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :pairing_sessions, :public_id, unique: true
    add_index :pairing_sessions, :token_digest, unique: true
    add_index :pairing_sessions,
      [:installation_id, :agent_id, :expires_at],
      name: "idx_pairing_sessions_installation_agent_expiry"
  end
end
