class CreateConversations < ActiveRecord::Migration[8.2]
  def change
    create_table :conversations do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.belongs_to :parent_conversation, foreign_key: { to_table: :conversations }
      t.string :kind, null: false
      t.string :purpose, null: false
      t.string :lifecycle_state, null: false
      t.bigint :historical_anchor_message_id

      t.timestamps
    end

    add_index :conversations, [:workspace_id, :purpose, :lifecycle_state], name: "idx_conversations_workspace_purpose_lifecycle"
  end
end
