class CreateProviderRequestControlsAndLeases < ActiveRecord::Migration[8.2]
  def change
    create_table :provider_request_controls do |t|
      t.references :installation, null: false, foreign_key: true
      t.string :provider_handle, null: false
      t.datetime :cooldown_until
      t.datetime :last_rate_limited_at
      t.string :last_rate_limit_reason
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :provider_request_controls, [:installation_id, :provider_handle], unique: true

    create_table :provider_request_leases do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workflow_run, null: true, foreign_key: true
      t.references :workflow_node, null: true, foreign_key: true
      t.string :provider_handle, null: false
      t.string :lease_token, null: false
      t.datetime :acquired_at, null: false
      t.datetime :last_heartbeat_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :released_at
      t.string :release_reason
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :provider_request_leases, :lease_token, unique: true
    add_index :provider_request_leases, [:installation_id, :provider_handle, :released_at], name: "idx_provider_request_leases_scope"
    add_index :provider_request_leases, [:installation_id, :provider_handle, :expires_at], name: "idx_provider_request_leases_expiry"
  end
end
