class CreateChannelConnectors < ActiveRecord::Migration[8.2]
  def change
    create_table :channel_connectors do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :ingress_binding, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :platform, null: false
      t.string :driver, null: false
      t.string :transport_kind, null: false
      t.string :label, null: false
      t.string :lifecycle_state, null: false, default: "active"
      t.jsonb :credential_ref_payload, null: false, default: {}
      t.jsonb :config_payload, null: false, default: {}
      t.jsonb :runtime_state_payload, null: false, default: {}

      t.timestamps
    end

    add_index :channel_connectors, :public_id, unique: true
    add_index :channel_connectors,
      :ingress_binding_id,
      unique: true,
      where: "lifecycle_state = 'active'",
      name: "idx_channel_connectors_active_binding"
  end
end
