class AddClosedAtToConversationSupervisionSessions < ActiveRecord::Migration[8.0]
  def up
    add_column :conversation_supervision_sessions, :closed_at, :datetime
    add_index :conversation_supervision_sessions,
      [:lifecycle_state, :closed_at],
      name: "idx_css_lifecycle_closed_at"

    execute <<~SQL.squish
      UPDATE conversation_supervision_sessions
      SET closed_at = updated_at
      WHERE lifecycle_state = 'closed' AND closed_at IS NULL
    SQL
  end

  def down
    remove_index :conversation_supervision_sessions, name: "idx_css_lifecycle_closed_at"
    remove_column :conversation_supervision_sessions, :closed_at
  end
end
