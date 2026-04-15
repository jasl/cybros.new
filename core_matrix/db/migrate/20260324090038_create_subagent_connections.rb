class CreateSubagentConnections < ActiveRecord::Migration[8.2]
  def change
    create_table :subagent_connections do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :workspace, foreign_key: true
      t.references :agent, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :owner_conversation, null: false, foreign_key: { to_table: :conversations }
      t.references :origin_turn, foreign_key: { to_table: :turns }
      t.references :parent_subagent_connection, foreign_key: { to_table: :subagent_connections }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :scope, null: false, default: "turn"
      t.string :profile_key, null: false
      t.string :resolved_model_selector_hint
      t.integer :depth, null: false, default: 0
      t.string :observed_status, null: false, default: "idle"
      t.string :supervision_state, null: false, default: "queued"
      t.string :focus_kind, null: false, default: "general"
      t.string :request_summary
      t.string :current_focus_summary
      t.string :recent_progress_summary
      t.string :waiting_summary
      t.string :blocked_summary
      t.string :next_step_hint
      t.datetime :last_progress_at
      t.jsonb :supervision_payload, null: false, default: {}
      t.string :close_state, null: false, default: "open"
      t.string :close_reason_kind
      t.datetime :close_requested_at
      t.datetime :close_grace_deadline_at
      t.datetime :close_force_deadline_at
      t.datetime :close_acknowledged_at
      t.string :close_outcome_kind
      t.jsonb :close_outcome_payload, null: false, default: {}

      t.timestamps
    end

    add_index :subagent_connections, :public_id, unique: true
    add_index :subagent_connections,
      [:owner_conversation_id, :created_at],
      name: "idx_subagent_connections_owner_created"
    add_index :subagent_connections,
      [:conversation_id],
      unique: true,
      name: "idx_subagent_connections_conversation"
  end
end
