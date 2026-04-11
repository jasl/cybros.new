class CreateTurnTodoPlans < ActiveRecord::Migration[8.2]
  def up
    create_table :turn_todo_plans do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :agent_task_run, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: true
      t.references :turn, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :status, null: false, default: "draft"
      t.string :goal_summary, null: false
      t.string :current_item_key
      t.jsonb :counts_payload, null: false, default: {}
      t.datetime :closed_at
      t.timestamps
    end

    add_index :turn_todo_plans, :public_id, unique: true
    add_index :turn_todo_plans,
      :agent_task_run_id,
      unique: true,
      where: "status = 'active'",
      name: "idx_turn_todo_plans_single_active_plan"

    create_table :turn_todo_plan_items do |t|
      t.references :turn_todo_plan, null: false, foreign_key: { on_delete: :cascade }
      t.references :installation, null: false, foreign_key: true
      t.references :delegated_subagent_connection, foreign_key: { to_table: :subagent_connections }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :item_key, null: false
      t.string :title, null: false
      t.string :status, null: false, default: "pending"
      t.integer :position, null: false, default: 0
      t.string :kind, null: false
      t.jsonb :details_payload, null: false, default: {}
      t.jsonb :depends_on_item_keys, null: false, default: []
      t.datetime :last_status_changed_at
      t.timestamps
    end

    add_index :turn_todo_plan_items, :public_id, unique: true
    add_index :turn_todo_plan_items,
      [:turn_todo_plan_id, :item_key],
      unique: true,
      name: "idx_turn_todo_plan_items_plan_key"
  end

  def down
    drop_table :turn_todo_plan_items, if_exists: true
    drop_table :turn_todo_plans, if_exists: true
  end
end
