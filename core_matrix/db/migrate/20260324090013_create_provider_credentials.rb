class CreateProviderCredentials < ActiveRecord::Migration[8.2]
  def change
    create_table :provider_credentials do |t|
      t.references :installation, null: false, foreign_key: true
      t.string :provider_handle, null: false
      t.string :credential_kind, null: false
      t.text :secret, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :last_rotated_at, null: false

      t.timestamps
    end

    add_index :provider_credentials, [:installation_id, :provider_handle, :credential_kind], unique: true, name: "idx_provider_credentials_installation_provider_kind"
  end
end
