class CreateConversations < ActiveRecord::Migration[8.2]
  def change
    create_table :conversations do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.belongs_to :parent_conversation, foreign_key: { to_table: :conversations }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :kind, null: false
      t.string :purpose, null: false
      t.string :lifecycle_state, null: false
      t.bigint :historical_anchor_message_id

      t.timestamps
    end

    add_index :conversations, [:workspace_id, :purpose, :lifecycle_state], name: "idx_conversations_workspace_purpose_lifecycle"
    add_index :conversations, :public_id, unique: true
  end
end
