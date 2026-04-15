class CreateIngressBindings < ActiveRecord::Migration[8.2]
  def change
    create_table :ingress_bindings do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workspace_agent, null: false, foreign_key: true
      t.references :default_execution_runtime, foreign_key: { to_table: :execution_runtimes }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :kind, null: false, default: "channel"
      t.string :lifecycle_state, null: false, default: "active"
      t.string :public_ingress_id, null: false
      t.string :ingress_secret_digest, null: false
      t.jsonb :routing_policy_payload, null: false, default: {}
      t.jsonb :manual_entry_policy,
        null: false,
        default: {
          "allow_app_entry" => true,
          "allow_external_entry" => true,
        }

      t.timestamps
    end

    add_index :ingress_bindings, :public_id, unique: true
    add_index :ingress_bindings, :public_ingress_id, unique: true
    add_index :ingress_bindings, :ingress_secret_digest, unique: true
  end
end
