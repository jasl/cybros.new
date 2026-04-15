class CreateWorkspaceAgents < ActiveRecord::Migration[8.2]
  def change
    create_table :workspace_agents do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true
      t.references :default_execution_runtime, foreign_key: { to_table: :execution_runtimes }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :lifecycle_state, null: false, default: "active"
      t.datetime :revoked_at
      t.string :revoked_reason_kind
      t.text :global_instructions
      t.jsonb :capability_policy_payload, null: false, default: {}
      t.jsonb :entry_policy_payload, null: false, default: {}

      t.timestamps
    end

    add_index :workspace_agents, :public_id, unique: true
    add_index :workspace_agents, [:workspace_id, :agent_id],
      unique: true,
      where: "lifecycle_state = 'active'",
      name: "idx_workspace_agents_active_workspace_agent"
    add_foreign_key :ingress_bindings, :workspace_agents
    add_foreign_key :conversations, :workspace_agents
  end
end
