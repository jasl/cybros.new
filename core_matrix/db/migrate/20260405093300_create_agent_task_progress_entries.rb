class CreateAgentTaskProgressEntries < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_task_progress_entries do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :agent_task_run, null: false, foreign_key: { on_delete: :cascade }
      t.references :subagent_connection, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.integer :sequence, null: false
      t.string :entry_kind, null: false
      t.string :summary, null: false
      t.jsonb :details_payload, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :agent_task_progress_entries, :public_id, unique: true
    add_index :agent_task_progress_entries,
      [:agent_task_run_id, :sequence],
      unique: true,
      name: "idx_agent_task_progress_entries_task_sequence"
  end
end
