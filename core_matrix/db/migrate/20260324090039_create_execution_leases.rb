class CreateExecutionLeases < ActiveRecord::Migration[8.2]
  def change
    create_table :execution_leases do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workflow_run, null: false, foreign_key: true
      t.references :workflow_node, null: false, foreign_key: true
      t.references :leased_resource, null: false, polymorphic: true, index: false
      t.string :holder_key, null: false
      t.integer :heartbeat_timeout_seconds, null: false
      t.datetime :acquired_at, null: false
      t.datetime :last_heartbeat_at, null: false
      t.datetime :released_at
      t.string :release_reason
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :execution_leases, [:leased_resource_type, :leased_resource_id], name: "idx_execution_leases_resource"
    add_index :execution_leases,
      [:leased_resource_type, :leased_resource_id],
      unique: true,
      where: "released_at IS NULL",
      name: "idx_execution_leases_active_resource"
    add_index :execution_leases, [:workflow_run_id, :released_at], name: "idx_execution_leases_run_released"
    add_index :execution_leases, [:holder_key, :released_at], name: "idx_execution_leases_holder_released"
  end
end
