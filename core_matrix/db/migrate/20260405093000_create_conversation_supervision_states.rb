class CreateConversationSupervisionStates < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_supervision_states do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :workspace, foreign_key: true
      t.references :agent, foreign_key: true
      t.references :target_conversation,
        null: false,
        foreign_key: { to_table: :conversations },
        index: { unique: true, name: "idx_conversation_supervision_states_target" }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :overall_state, null: false, default: "idle"
      t.string :last_terminal_state
      t.datetime :last_terminal_at
      t.string :current_owner_kind
      t.string :current_owner_public_id
      t.string :request_summary
      t.string :current_focus_summary
      t.string :recent_progress_summary
      t.string :waiting_summary
      t.string :blocked_summary
      t.string :next_step_hint
      t.datetime :last_progress_at
      t.string :board_lane, null: false, default: "idle"
      t.datetime :lane_changed_at
      t.datetime :retry_due_at
      t.integer :active_plan_item_count, null: false, default: 0
      t.integer :completed_plan_item_count, null: false, default: 0
      t.integer :active_subagent_count, null: false, default: 0
      t.jsonb :board_badges, null: false, default: []
      t.integer :projection_version, null: false, default: 0
      t.timestamps
    end

    create_table :conversation_supervision_state_details do |t|
      t.references :conversation_supervision_state,
        null: false,
        foreign_key: { on_delete: :cascade },
        index: { unique: true }
      t.jsonb :status_payload, null: false, default: {}

      t.timestamps
    end

    add_index :conversation_supervision_states, :public_id, unique: true
  end
end
