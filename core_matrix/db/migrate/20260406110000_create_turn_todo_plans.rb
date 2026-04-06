class CreateTurnTodoPlans < ActiveRecord::Migration[8.2]
  def change
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
  end
end
