class InlineWorkspacePolicyIntoWorkspaces < ActiveRecord::Migration[8.2]
  def up
    add_column :workspaces, :disabled_capabilities, :jsonb, null: false, default: []

    execute <<~SQL
      UPDATE workspaces
      SET disabled_capabilities = workspace_policies.disabled_capabilities
      FROM workspace_policies
      WHERE workspace_policies.workspace_id = workspaces.id
    SQL

    drop_table :workspace_policies
  end

  def down
    create_table :workspace_policies do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :disabled_capabilities, null: false, default: []
      t.timestamps
    end

    execute <<~SQL
      INSERT INTO workspace_policies (
        installation_id,
        workspace_id,
        disabled_capabilities,
        created_at,
        updated_at
      )
      SELECT
        installation_id,
        id,
        disabled_capabilities,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM workspaces
      WHERE disabled_capabilities <> '[]'::jsonb
    SQL

    remove_column :workspaces, :disabled_capabilities
  end
end
