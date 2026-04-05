class AddAgentControlContract < ActiveRecord::Migration[8.2]
  def change
    create_table :execution_capability_snapshots do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :tool_surface_document, null: false, foreign_key: { to_table: :json_documents }
      t.references :subagent_session, foreign_key: true
      t.references :parent_subagent_session, foreign_key: { to_table: :subagent_sessions }
      t.references :owner_conversation, foreign_key: { to_table: :conversations }
      t.uuid :public_id, default: -> { "uuidv7()" }, null: false
      t.string :fingerprint, null: false
      t.string :program_version_fingerprint, null: false
      t.string :profile_key, null: false
      t.boolean :subagent, null: false, default: false
      t.integer :subagent_depth
      t.jsonb :subagent_policy_snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :execution_capability_snapshots, :public_id, unique: true
    add_index :execution_capability_snapshots,
      [:installation_id, :fingerprint],
      unique: true,
      name: "idx_execution_capability_snapshots_fingerprint"

    create_table :execution_context_snapshots do |t|
      t.references :installation, null: false, foreign_key: true
      t.uuid :public_id, default: -> { "uuidv7()" }, null: false
      t.string :fingerprint, null: false
      t.string :projection_fingerprint, null: false
      t.jsonb :message_refs, null: false, default: []
      t.jsonb :import_refs, null: false, default: []
      t.jsonb :attachment_refs, null: false, default: []
      t.timestamps
    end
    add_index :execution_context_snapshots, :public_id, unique: true
    add_index :execution_context_snapshots,
      [:installation_id, :fingerprint],
      unique: true,
      name: "idx_execution_context_snapshots_fingerprint"

    create_table :execution_contracts do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :turn, null: false, foreign_key: true, index: { unique: true }
      t.references :agent_program_version, null: false, foreign_key: true
      t.references :execution_runtime, foreign_key: true
      t.references :selected_input_message, foreign_key: { to_table: :messages }
      t.references :selected_output_message, foreign_key: { to_table: :messages }
      t.references :execution_capability_snapshot, null: false, foreign_key: true
      t.references :execution_context_snapshot, null: false, foreign_key: true
      t.uuid :public_id, default: -> { "uuidv7()" }, null: false
      t.jsonb :provider_context, null: false, default: {}
      t.jsonb :turn_origin, null: false, default: {}
      t.jsonb :attachment_manifest, null: false, default: []
      t.jsonb :model_input_attachments, null: false, default: []
      t.jsonb :attachment_diagnostics, null: false, default: []
      t.timestamps
    end
    add_index :execution_contracts, :public_id, unique: true

    add_reference :turns, :execution_contract, foreign_key: true

    create_table :agent_sessions do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :agent_program, null: false, foreign_key: true
      t.references :agent_program_version, null: false, foreign_key: true
      t.uuid :public_id, default: -> { "uuidv7()" }, null: false
      t.string :session_credential_digest, null: false
      t.string :session_token_digest, null: false
      t.jsonb :endpoint_metadata, null: false, default: {}
      t.string :lifecycle_state, null: false, default: "active"
      t.string :health_status, null: false, default: "pending"
      t.jsonb :health_metadata, null: false, default: {}
      t.boolean :auto_resume_eligible, null: false, default: false
      t.string :unavailability_reason
      t.string :control_activity_state, null: false, default: "idle"
      t.datetime :last_heartbeat_at
      t.datetime :last_health_check_at
      t.datetime :last_control_activity_at
      t.timestamps
    end
    add_index :agent_sessions, :public_id, unique: true
    add_index :agent_sessions, :session_credential_digest, unique: true
    add_index :agent_sessions, :session_token_digest, unique: true
    add_index :agent_sessions, :agent_program_id,
      unique: true,
      where: "lifecycle_state = 'active'",
      name: "idx_agent_sessions_agent_program_active"

    create_table :execution_sessions do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :execution_runtime, null: false, foreign_key: true
      t.uuid :public_id, default: -> { "uuidv7()" }, null: false
      t.string :session_credential_digest, null: false
      t.string :session_token_digest, null: false
      t.jsonb :endpoint_metadata, null: false, default: {}
      t.string :lifecycle_state, null: false, default: "active"
      t.datetime :last_heartbeat_at
      t.timestamps
    end
    add_index :execution_sessions, :public_id, unique: true
    add_index :execution_sessions, :session_credential_digest, unique: true
    add_index :execution_sessions, :session_token_digest, unique: true
    add_index :execution_sessions, :execution_runtime_id,
      unique: true,
      where: "lifecycle_state = 'active'",
      name: "idx_execution_sessions_runtime_active"

    create_table :agent_task_runs do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :agent_program, null: false, foreign_key: true
      t.references :workflow_run, null: false, foreign_key: true
      t.references :workflow_node, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :turn, null: false, foreign_key: true
      t.references :subagent_session, foreign_key: true
      t.references :origin_turn, foreign_key: { to_table: :turns }
      t.references :holder_agent_session, foreign_key: { to_table: :agent_sessions }
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
      t.references :target_agent_program, null: false, foreign_key: { to_table: :agent_programs }
      t.references :target_agent_program_version, foreign_key: { to_table: :agent_program_versions }
      t.references :target_execution_runtime, foreign_key: { to_table: :execution_runtimes }
      t.references :agent_task_run, foreign_key: true
      t.references :workflow_node, foreign_key: true
      t.references :execution_contract, foreign_key: true
      t.references :payload_document, foreign_key: { to_table: :json_documents }
      t.references :leased_to_agent_session, foreign_key: { to_table: :agent_sessions }
      t.references :leased_to_execution_session, foreign_key: { to_table: :execution_sessions }
      t.uuid :public_id, default: -> { "uuidv7()" }, null: false
      t.string :item_type, null: false
      t.string :runtime_plane, null: false
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
    add_index :agent_control_mailbox_items, [:target_agent_program_id, :runtime_plane, :status, :priority, :available_at], name: "idx_agent_control_mailbox_program_delivery"
    add_index :agent_control_mailbox_items, [:target_agent_program_version_id, :runtime_plane, :status, :priority, :available_at], name: "idx_agent_control_mailbox_program_version_delivery"
    add_index :agent_control_mailbox_items, [:target_execution_runtime_id, :runtime_plane, :status, :priority, :available_at], name: "idx_agent_control_mailbox_execution_delivery"

    create_table :agent_control_report_receipts do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :agent_session, foreign_key: true
      t.references :execution_session, foreign_key: { to_table: :execution_sessions }
      t.references :agent_task_run, foreign_key: true
      t.references :mailbox_item, foreign_key: { to_table: :agent_control_mailbox_items }
      t.string :protocol_message_id, null: false
      t.string :method_id, null: false
      t.string :logical_work_id
      t.integer :attempt_no
      t.string :result_code, null: false
      t.references :report_document, foreign_key: { to_table: :json_documents }
      t.timestamps
    end
    add_index :agent_control_report_receipts, [:installation_id, :protocol_message_id], unique: true, name: "idx_agent_control_report_receipts_protocol_message"

    change_table :process_runs, bulk: true do |t|
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :close_state, null: false, default: "open"
      t.string :close_reason_kind
      t.datetime :close_requested_at
      t.datetime :close_grace_deadline_at
      t.datetime :close_force_deadline_at
      t.datetime :close_acknowledged_at
      t.string :close_outcome_kind
      t.jsonb :close_outcome_payload, null: false, default: {}
    end

    add_index :process_runs, :public_id, unique: true

    change_table :subagent_sessions, bulk: true do |t|
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :close_state, null: false, default: "open"
      t.string :close_reason_kind
      t.datetime :close_requested_at
      t.datetime :close_grace_deadline_at
      t.datetime :close_force_deadline_at
      t.datetime :close_acknowledged_at
      t.string :close_outcome_kind
      t.jsonb :close_outcome_payload, null: false, default: {}
    end

    add_index :subagent_sessions, :public_id, unique: true
  end
end
