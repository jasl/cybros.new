class CreateProviderEntitlements < ActiveRecord::Migration[8.2]
  def change
    create_table :provider_entitlements do |t|
      t.references :installation, null: false, foreign_key: true
      t.string :provider_handle, null: false
      t.string :entitlement_key, null: false
      t.string :window_kind, null: false
      t.integer :window_seconds
      t.integer :quota_limit, null: false
      t.boolean :active, null: false, default: true
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :provider_entitlements, [:installation_id, :provider_handle, :entitlement_key], unique: true, name: "idx_provider_entitlements_installation_provider_key"
  end
end
