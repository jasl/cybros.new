class CreateConversations < ActiveRecord::Migration[8.2]
  def change
    create_table :conversations do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true
      t.references :current_execution_runtime, foreign_key: { to_table: :execution_runtimes }
      t.belongs_to :parent_conversation, foreign_key: { to_table: :conversations }
      t.bigint :current_execution_epoch_id
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :kind, null: false
      t.string :purpose, null: false
      t.string :addressability, null: false, default: "owner_addressable"
      t.string :lifecycle_state, null: false
      t.string :deletion_state, null: false, default: "retained"
      t.string :execution_continuity_state, null: false, default: "ready"
      t.datetime :deleted_at
      t.bigint :historical_anchor_message_id
      t.text :title
      t.text :summary
      t.string :title_source, null: false, default: "none"
      t.string :summary_source, null: false, default: "none"
      t.string :title_lock_state, null: false, default: "unlocked"
      t.string :summary_lock_state, null: false, default: "unlocked"
      t.datetime :title_updated_at
      t.datetime :summary_updated_at

      t.timestamps
    end

    add_index :conversations, [:workspace_id, :purpose, :lifecycle_state], name: "idx_conversations_workspace_purpose_lifecycle"
    add_index :conversations, [:agent_id, :lifecycle_state], name: "idx_conversations_agent_lifecycle"
    add_index :conversations, :current_execution_epoch_id
    add_index :conversations, :public_id, unique: true
    add_check_constraint :conversations,
      "(deletion_state IN ('retained', 'pending_delete', 'deleted'))",
      name: "chk_conversations_deletion_state"
    add_check_constraint :conversations,
      "(title_source IN ('none', 'bootstrap', 'generated', 'agent', 'user'))",
      name: "chk_conversations_title_source"
    add_check_constraint :conversations,
      "(summary_source IN ('none', 'bootstrap', 'generated', 'agent', 'user'))",
      name: "chk_conversations_summary_source"
    add_check_constraint :conversations,
      "(title_lock_state IN ('unlocked', 'user_locked'))",
      name: "chk_conversations_title_lock_state"
    add_check_constraint :conversations,
      "(summary_lock_state IN ('unlocked', 'user_locked'))",
      name: "chk_conversations_summary_lock_state"
    add_check_constraint :conversations,
      "((deletion_state = 'retained' AND deleted_at IS NULL) OR (deletion_state IN ('pending_delete', 'deleted') AND deleted_at IS NOT NULL))",
      name: "chk_conversations_deleted_at_consistency"
  end
end
