class CreateWorkflowRuns < ActiveRecord::Migration[8.2]
  def change
    create_table :workflow_runs do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :turn, null: false, foreign_key: true, index: { unique: true }
      t.string :lifecycle_state, null: false, default: "active"

      t.timestamps
    end

    add_index :workflow_runs,
      :conversation_id,
      unique: true,
      where: "((lifecycle_state)::text = 'active'::text)",
      name: "index_workflow_runs_on_conversation_id_active"
  end
end
