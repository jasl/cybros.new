class CreateConversationCapabilityPolicies < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_capability_policies do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :target_conversation,
        null: false,
        foreign_key: { to_table: :conversations },
        index: { unique: true, name: "idx_conversation_capability_policies_target" }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.boolean :supervision_enabled, null: false, default: false
      t.boolean :detailed_progress_enabled, null: false, default: false
      t.boolean :side_chat_enabled, null: false, default: false
      t.boolean :control_enabled, null: false, default: false
      t.jsonb :policy_payload, null: false, default: {}
      t.timestamps
    end

    add_index :conversation_capability_policies, :public_id, unique: true
  end
end
