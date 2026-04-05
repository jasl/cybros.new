class CreateConversationCapabilityGrants < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_capability_grants do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :target_conversation, null: false, foreign_key: { to_table: :conversations }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :grantee_kind, null: false
      t.string :grantee_public_id, null: false
      t.string :capability, null: false
      t.string :grant_state, null: false, default: "active"
      t.jsonb :policy_payload, null: false, default: {}
      t.datetime :expires_at
      t.timestamps
    end

    add_index :conversation_capability_grants, :public_id, unique: true
    add_index :conversation_capability_grants,
      [:target_conversation_id, :grantee_kind, :grantee_public_id, :capability],
      name: "idx_conversation_capability_grants_lookup"
  end
end
