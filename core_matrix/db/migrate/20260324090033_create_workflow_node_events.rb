class CreateWorkflowNodeEvents < ActiveRecord::Migration[8.2]
  def change
    create_table :workflow_node_events do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workflow_run, null: false, foreign_key: true
      t.references :workflow_node, null: false, foreign_key: true
      t.integer :ordinal, null: false
      t.string :event_kind, null: false
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :workflow_node_events, [:workflow_node_id, :ordinal], unique: true
    add_index :workflow_node_events, [:workflow_run_id, :event_kind]
  end
end
