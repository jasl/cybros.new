class AddAgentControlContract < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_task_runs do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :agent_installation, null: false, foreign_key: true
      t.references :workflow_run, null: false, foreign_key: true
      t.references :workflow_node, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :turn, null: false, foreign_key: true
      t.references :subagent_session, foreign_key: true
      t.references :origin_turn, foreign_key: { to_table: :turns }
      t.references :holder_agent_deployment, foreign_key: { to_table: :agent_deployments }
      t.uuid :public_id, default: -> { "uuidv7()" }, null: false
      t.string :kind, null: false
      t.string :lifecycle_state, null: false, default: "queued"
      t.string :logical_work_id, null: false
      t.integer :attempt_no, null: false, default: 1
      t.jsonb :task_payload, null: false, default: {}
      t.jsonb :progress_payload, null: false, default: {}
      t.jsonb :terminal_payload, null: false, default: {}
      t.integer :expected_duration_seconds
      t.datetime :started_at
      t.datetime :finished_at
      t.string :close_state, null: false, default: "open"
      t.string :close_reason_kind
      t.datetime :close_requested_at
      t.datetime :close_grace_deadline_at
      t.datetime :close_force_deadline_at
      t.datetime :close_acknowledged_at
      t.string :close_outcome_kind
      t.jsonb :close_outcome_payload, null: false, default: {}
      t.timestamps
    end
    add_index :agent_task_runs, :public_id, unique: true
    add_index :agent_task_runs, [:workflow_run_id, :logical_work_id, :attempt_no], unique: true, name: "idx_agent_task_runs_work_attempt"

    create_table :agent_control_mailbox_items do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :target_agent_installation, null: false, foreign_key: { to_table: :agent_installations }
      t.references :target_agent_deployment, foreign_key: { to_table: :agent_deployments }
      t.references :target_execution_environment, foreign_key: { to_table: :execution_environments }
      t.references :agent_task_run, foreign_key: true
      t.references :leased_to_agent_deployment, foreign_key: { to_table: :agent_deployments }
      t.uuid :public_id, default: -> { "uuidv7()" }, null: false
      t.string :item_type, null: false
      t.string :runtime_plane, null: false
      t.string :target_kind, null: false
      t.string :target_ref, null: false
      t.string :logical_work_id, null: false
      t.integer :attempt_no, null: false, default: 1
      t.integer :delivery_no, null: false, default: 0
      t.string :protocol_message_id, null: false
      t.string :causation_id
      t.integer :priority, null: false, default: 1
      t.string :status, null: false, default: "queued"
      t.datetime :available_at, null: false
      t.datetime :dispatch_deadline_at, null: false
      t.integer :lease_timeout_seconds, null: false, default: 30
      t.datetime :execution_hard_deadline_at
      t.jsonb :payload, null: false, default: {}
      t.datetime :leased_at
      t.datetime :lease_expires_at
      t.datetime :acked_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.timestamps
    end
    add_index :agent_control_mailbox_items, :public_id, unique: true
    add_index :agent_control_mailbox_items, [:installation_id, :protocol_message_id], unique: true, name: "idx_agent_control_mailbox_items_protocol_message"
    add_index :agent_control_mailbox_items, [:target_agent_installation_id, :runtime_plane, :status, :priority, :available_at], name: "idx_agent_control_mailbox_installation_delivery"
    add_index :agent_control_mailbox_items, [:target_agent_deployment_id, :runtime_plane, :status, :priority, :available_at], name: "idx_agent_control_mailbox_deployment_delivery"
    add_index :agent_control_mailbox_items, [:target_execution_environment_id, :runtime_plane, :status, :priority, :available_at], name: "idx_agent_control_mailbox_environment_delivery"

    create_table :agent_control_report_receipts do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :agent_deployment, null: false, foreign_key: true
      t.references :agent_task_run, foreign_key: true
      t.references :mailbox_item, foreign_key: { to_table: :agent_control_mailbox_items }
      t.string :protocol_message_id, null: false
      t.string :method_id, null: false
      t.string :logical_work_id
      t.integer :attempt_no
      t.string :result_code, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
    add_index :agent_control_report_receipts, [:installation_id, :protocol_message_id], unique: true, name: "idx_agent_control_report_receipts_protocol_message"

    add_column :agent_deployments, :realtime_link_state, :string, null: false, default: "disconnected"
    add_column :agent_deployments, :control_activity_state, :string, null: false, default: "offline"
    add_column :agent_deployments, :last_control_activity_at, :datetime

    add_column :process_runs, :public_id, :uuid, null: false, default: -> { "uuidv7()" }
    add_column :process_runs, :close_state, :string, null: false, default: "open"
    add_column :process_runs, :close_reason_kind, :string
    add_column :process_runs, :close_requested_at, :datetime
    add_column :process_runs, :close_grace_deadline_at, :datetime
    add_column :process_runs, :close_force_deadline_at, :datetime
    add_column :process_runs, :close_acknowledged_at, :datetime
    add_column :process_runs, :close_outcome_kind, :string
    add_column :process_runs, :close_outcome_payload, :jsonb, null: false, default: {}
    add_index :process_runs, :public_id, unique: true

    add_column :subagent_sessions, :public_id, :uuid, null: false, default: -> { "uuidv7()" }
    add_column :subagent_sessions, :close_state, :string, null: false, default: "open"
    add_column :subagent_sessions, :close_reason_kind, :string
    add_column :subagent_sessions, :close_requested_at, :datetime
    add_column :subagent_sessions, :close_grace_deadline_at, :datetime
    add_column :subagent_sessions, :close_force_deadline_at, :datetime
    add_column :subagent_sessions, :close_acknowledged_at, :datetime
    add_column :subagent_sessions, :close_outcome_kind, :string
    add_column :subagent_sessions, :close_outcome_payload, :jsonb, null: false, default: {}
    add_index :subagent_sessions, :public_id, unique: true
  end
end
