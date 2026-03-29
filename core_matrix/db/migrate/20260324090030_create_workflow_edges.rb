class CreateWorkflowEdges < ActiveRecord::Migration[8.2]
  def change
    create_table :workflow_edges do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workflow_run, null: false, foreign_key: true
      t.references :from_node, null: false, foreign_key: { to_table: :workflow_nodes }
      t.references :to_node, null: false, foreign_key: { to_table: :workflow_nodes }
      t.integer :ordinal, null: false
      t.string :requirement, null: false, default: "required"

      t.timestamps
    end

    add_index :workflow_edges, [:workflow_run_id, :from_node_id, :ordinal], unique: true
    add_index :workflow_edges, [:workflow_run_id, :from_node_id, :to_node_id], unique: true
    add_check_constraint :workflow_edges,
      "(requirement IN ('required', 'optional'))",
      name: "chk_workflow_edges_requirement"
  end
end
