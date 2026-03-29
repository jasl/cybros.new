class CreateSubagentSessions < ActiveRecord::Migration[8.2]
  def change
    create_table :subagent_sessions do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :owner_conversation, null: false, foreign_key: { to_table: :conversations }
      t.references :origin_turn, foreign_key: { to_table: :turns }
      t.references :parent_subagent_session, foreign_key: { to_table: :subagent_sessions }
      t.string :scope, null: false, default: "turn"
      t.string :profile_key, null: false
      t.integer :depth, null: false, default: 0
      t.string :observed_status, null: false, default: "idle"

      t.timestamps
    end

    add_index :subagent_sessions,
      [:owner_conversation_id, :created_at],
      name: "idx_subagent_sessions_owner_created"
    add_index :subagent_sessions,
      [:conversation_id],
      unique: true,
      name: "idx_subagent_sessions_conversation"
  end
end
