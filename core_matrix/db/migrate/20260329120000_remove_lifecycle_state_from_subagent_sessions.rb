class RemoveLifecycleStateFromSubagentSessions < ActiveRecord::Migration[8.2]
  EXPECTED_LIFECYCLE_BY_CLOSE_STATE = {
    "open" => "open",
    "requested" => "close_requested",
    "acknowledged" => "close_requested",
    "closed" => "closed",
    "failed" => "closed",
  }.freeze

  def up
    mismatches = select_rows(<<~SQL.squish)
      SELECT public_id, close_state, lifecycle_state
      FROM subagent_sessions
      WHERE (close_state = 'open' AND lifecycle_state <> 'open')
         OR (close_state IN ('requested', 'acknowledged') AND lifecycle_state <> 'close_requested')
         OR (close_state IN ('closed', 'failed') AND lifecycle_state <> 'closed')
      ORDER BY id
      LIMIT 5
    SQL

    if mismatches.any?
      raise ActiveRecord::IrreversibleMigration,
        "Cannot remove subagent_sessions.lifecycle_state with inconsistent close_state mapping: #{format_mismatches(mismatches)}"
    end

    remove_column :subagent_sessions, :lifecycle_state, :string
  end

  def down
    add_column :subagent_sessions, :lifecycle_state, :string, null: false, default: "open"

    EXPECTED_LIFECYCLE_BY_CLOSE_STATE.each do |close_state, lifecycle_state|
      execute <<~SQL.squish
        UPDATE subagent_sessions
        SET lifecycle_state = #{quote(lifecycle_state)}
        WHERE close_state = #{quote(close_state)}
      SQL
    end
  end

  private

  def format_mismatches(rows)
    rows.map { |public_id, close_state, lifecycle_state| "#{public_id}:#{close_state}->#{lifecycle_state}" }.join(", ")
  end
end
