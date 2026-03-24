class CreateWorkflowNodes < ActiveRecord::Migration[8.2]
  def change
    create_table :workflow_nodes do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workflow_run, null: false, foreign_key: true
      t.integer :ordinal, null: false
      t.string :node_key, null: false
      t.string :node_type, null: false
      t.string :decision_source, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :workflow_nodes, [:workflow_run_id, :ordinal], unique: true
    add_index :workflow_nodes, [:workflow_run_id, :node_key], unique: true
  end
end
