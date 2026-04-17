class CreateProviderAuthorizationSessions < ActiveRecord::Migration[8.2]
  def change
    create_table :provider_authorization_sessions do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :issued_by_user, foreign_key: { to_table: :users }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :provider_handle, null: false
      t.text :device_auth_id, null: false
      t.string :user_code, null: false
      t.string :verification_uri, null: false
      t.integer :poll_interval_seconds, null: false, default: 5
      t.string :status, null: false, default: "pending"
      t.datetime :issued_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :completed_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :provider_authorization_sessions, :public_id, unique: true
    add_index :provider_authorization_sessions,
      [:installation_id, :provider_handle, :status, :issued_at],
      name: "idx_provider_auth_sessions_installation_provider_status_issued"
  end
end
