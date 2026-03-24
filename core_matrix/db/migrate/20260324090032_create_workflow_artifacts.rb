class CreateWorkflowArtifacts < ActiveRecord::Migration[8.2]
  def change
    create_table :workflow_artifacts do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workflow_run, null: false, foreign_key: true
      t.references :workflow_node, null: false, foreign_key: true
      t.string :artifact_key, null: false
      t.string :artifact_kind, null: false
      t.string :storage_mode, null: false
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :workflow_artifacts, [:workflow_run_id, :artifact_key]
    add_index :workflow_artifacts, [:workflow_node_id, :artifact_kind]
  end
end
