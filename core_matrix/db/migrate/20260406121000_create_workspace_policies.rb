class CreateWorkspacePolicies < ActiveRecord::Migration[8.2]
  def change
    create_table :workspace_policies do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :disabled_capabilities, null: false, default: []
      t.timestamps
    end
  end
end
