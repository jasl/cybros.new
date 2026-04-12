class CreateProviderConnectionChecks < ActiveRecord::Migration[8.2]
  def change
    create_table :provider_connection_checks do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :requested_by_user, foreign_key: { to_table: :users }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :provider_handle, null: false
      t.string :lifecycle_state, null: false, default: "queued"
      t.datetime :queued_at, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.jsonb :request_payload, null: false, default: {}
      t.jsonb :result_payload, null: false, default: {}
      t.jsonb :failure_payload, null: false, default: {}
      t.timestamps
    end

    add_index :provider_connection_checks, :public_id, unique: true
    add_index :provider_connection_checks, [:installation_id, :provider_handle], unique: true, name: "idx_provider_connection_checks_installation_provider"
  end
end
