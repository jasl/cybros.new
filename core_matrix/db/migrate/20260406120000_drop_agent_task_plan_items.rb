class DropAgentTaskPlanItems < ActiveRecord::Migration[8.0]
  def up
    drop_table :agent_task_plan_items, if_exists: true
  end

  def down
    create_table :agent_task_plan_items do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :agent_task_run, null: false, foreign_key: { on_delete: :cascade }
      t.references :parent_plan_item, null: true, foreign_key: { to_table: :agent_task_plan_items }
      t.references :delegated_subagent_session, null: true, foreign_key: { to_table: :subagent_sessions }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :item_key, null: false
      t.string :title, null: false
      t.string :status, null: false, default: "pending"
      t.integer :position, null: false, default: 0
      t.jsonb :details_payload, null: false, default: {}
      t.datetime :last_status_changed_at
      t.timestamps
    end

    add_index :agent_task_plan_items, :public_id, unique: true
  end
end
