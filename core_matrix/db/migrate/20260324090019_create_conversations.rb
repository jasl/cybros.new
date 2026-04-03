class CreateConversations < ActiveRecord::Migration[8.2]
  def change
    create_table :conversations do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.references :agent_program, null: false, foreign_key: true
      t.belongs_to :parent_conversation, foreign_key: { to_table: :conversations }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :kind, null: false
      t.string :purpose, null: false
      t.string :addressability, null: false, default: "owner_addressable"
      t.string :lifecycle_state, null: false
      t.string :deletion_state, null: false, default: "retained"
      t.datetime :deleted_at
      t.bigint :historical_anchor_message_id

      t.timestamps
    end

    add_index :conversations, [:workspace_id, :purpose, :lifecycle_state], name: "idx_conversations_workspace_purpose_lifecycle"
    add_index :conversations, [:agent_program_id, :lifecycle_state], name: "idx_conversations_program_lifecycle"
    add_index :conversations, :public_id, unique: true
    add_check_constraint :conversations,
      "(deletion_state IN ('retained', 'pending_delete', 'deleted'))",
      name: "chk_conversations_deletion_state"
    add_check_constraint :conversations,
      "((deletion_state = 'retained' AND deleted_at IS NULL) OR (deletion_state IN ('pending_delete', 'deleted') AND deleted_at IS NOT NULL))",
      name: "chk_conversations_deleted_at_consistency"
  end
end
