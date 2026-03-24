class CreateAgentDeployments < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_deployments do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.belongs_to :agent_installation, null: false, foreign_key: true
      t.belongs_to :execution_environment, null: false, foreign_key: true
      t.bigint :active_capability_snapshot_id
      t.string :fingerprint, null: false
      t.string :machine_credential_digest, null: false
      t.jsonb :endpoint_metadata, null: false, default: {}
      t.string :protocol_version, null: false
      t.string :sdk_version, null: false
      t.string :health_status, null: false, default: "offline"
      t.jsonb :health_metadata, null: false, default: {}
      t.datetime :last_heartbeat_at
      t.datetime :last_health_check_at
      t.string :unavailability_reason
      t.boolean :auto_resume_eligible, null: false, default: false
      t.string :bootstrap_state, null: false, default: "pending"

      t.timestamps
    end

    add_index :agent_deployments, :active_capability_snapshot_id
    add_index :agent_deployments, :machine_credential_digest, unique: true
    add_index :agent_deployments, [:installation_id, :fingerprint], unique: true
    add_index :agent_deployments, :agent_installation_id,
      unique: true,
      where: "bootstrap_state = 'active'",
      name: "index_agent_deployments_on_agent_installation_id_active"
  end
end
