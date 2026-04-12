# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.2].define(version: 2026_04_06_110000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_config_states", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.bigint "base_agent_definition_version_id", null: false
    t.string "content_fingerprint", null: false
    t.datetime "created_at", null: false
    t.bigint "effective_document_id", null: false
    t.bigint "installation_id", null: false
    t.bigint "override_document_id"
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "reconciliation_state", default: "ready", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["agent_id"], name: "index_agent_config_states_on_agent_id", unique: true
    t.index ["base_agent_definition_version_id"], name: "index_agent_config_states_on_base_agent_definition_version_id"
    t.index ["effective_document_id"], name: "index_agent_config_states_on_effective_document_id"
    t.index ["installation_id", "content_fingerprint"], name: "idx_agent_config_states_installation_fingerprint"
    t.index ["installation_id"], name: "index_agent_config_states_on_installation_id"
    t.index ["override_document_id"], name: "index_agent_config_states_on_override_document_id"
    t.index ["public_id"], name: "index_agent_config_states_on_public_id", unique: true
  end

  create_table "agent_connections", force: :cascade do |t|
    t.bigint "agent_definition_version_id", null: false
    t.bigint "agent_id", null: false
    t.boolean "auto_resume_eligible", default: false, null: false
    t.string "connection_credential_digest", null: false
    t.string "connection_token_digest", null: false
    t.string "control_activity_state", default: "idle", null: false
    t.datetime "created_at", null: false
    t.jsonb "endpoint_metadata", default: {}, null: false
    t.jsonb "health_metadata", default: {}, null: false
    t.string "health_status", default: "pending", null: false
    t.bigint "installation_id", null: false
    t.datetime "last_control_activity_at"
    t.datetime "last_health_check_at"
    t.datetime "last_heartbeat_at"
    t.string "lifecycle_state", default: "active", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "unavailability_reason"
    t.datetime "updated_at", null: false
    t.index ["agent_definition_version_id"], name: "index_agent_connections_on_agent_definition_version_id"
    t.index ["agent_id"], name: "idx_agent_connections_agent_active", unique: true, where: "((lifecycle_state)::text = 'active'::text)"
    t.index ["agent_id"], name: "index_agent_connections_on_agent_id"
    t.index ["connection_credential_digest"], name: "index_agent_connections_on_connection_credential_digest", unique: true
    t.index ["connection_token_digest"], name: "index_agent_connections_on_connection_token_digest", unique: true
    t.index ["installation_id"], name: "index_agent_connections_on_installation_id"
    t.index ["public_id"], name: "index_agent_connections_on_public_id", unique: true
  end

  create_table "agent_control_mailbox_items", force: :cascade do |t|
    t.datetime "acked_at"
    t.bigint "agent_task_run_id"
    t.integer "attempt_no", default: 1, null: false
    t.datetime "available_at", null: false
    t.string "causation_id"
    t.datetime "completed_at"
    t.string "control_plane", null: false
    t.datetime "created_at", null: false
    t.integer "delivery_no", default: 0, null: false
    t.datetime "dispatch_deadline_at", null: false
    t.bigint "execution_contract_id"
    t.datetime "execution_hard_deadline_at"
    t.datetime "failed_at"
    t.bigint "installation_id", null: false
    t.string "item_type", null: false
    t.datetime "lease_expires_at"
    t.integer "lease_timeout_seconds", default: 30, null: false
    t.datetime "leased_at"
    t.bigint "leased_to_agent_connection_id"
    t.bigint "leased_to_execution_runtime_connection_id"
    t.string "logical_work_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.bigint "payload_document_id"
    t.integer "priority", default: 1, null: false
    t.string "protocol_message_id", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "status", default: "queued", null: false
    t.bigint "target_agent_definition_version_id"
    t.bigint "target_agent_id", null: false
    t.bigint "target_execution_runtime_id"
    t.datetime "updated_at", null: false
    t.bigint "workflow_node_id"
    t.index ["agent_task_run_id"], name: "index_agent_control_mailbox_items_on_agent_task_run_id"
    t.index ["execution_contract_id"], name: "index_agent_control_mailbox_items_on_execution_contract_id"
    t.index ["installation_id", "protocol_message_id"], name: "idx_agent_control_mailbox_items_protocol_message", unique: true
    t.index ["installation_id"], name: "index_agent_control_mailbox_items_on_installation_id"
    t.index ["leased_to_agent_connection_id"], name: "idx_on_leased_to_agent_connection_id_887e6562e3"
    t.index ["leased_to_execution_runtime_connection_id"], name: "idx_on_leased_to_execution_runtime_connection_id_0a933e2fd1"
    t.index ["payload_document_id"], name: "index_agent_control_mailbox_items_on_payload_document_id"
    t.index ["public_id"], name: "index_agent_control_mailbox_items_on_public_id", unique: true
    t.index ["target_agent_definition_version_id", "control_plane", "status", "priority", "available_at"], name: "idx_agent_control_mailbox_agent_definition_delivery"
    t.index ["target_agent_definition_version_id"], name: "idx_on_target_agent_definition_version_id_4f14cb9712"
    t.index ["target_agent_id", "control_plane", "status", "priority", "available_at"], name: "idx_agent_control_mailbox_agent_delivery"
    t.index ["target_agent_id"], name: "index_agent_control_mailbox_items_on_target_agent_id"
    t.index ["target_execution_runtime_id", "control_plane", "status", "priority", "available_at"], name: "idx_agent_control_mailbox_execution_delivery"
    t.index ["target_execution_runtime_id"], name: "idx_on_target_execution_runtime_id_d79214996d"
    t.index ["workflow_node_id"], name: "index_agent_control_mailbox_items_on_workflow_node_id"
  end

  create_table "agent_control_report_receipts", force: :cascade do |t|
    t.bigint "agent_connection_id"
    t.bigint "agent_task_run_id"
    t.integer "attempt_no"
    t.datetime "created_at", null: false
    t.bigint "execution_runtime_connection_id"
    t.bigint "installation_id", null: false
    t.string "logical_work_id"
    t.bigint "mailbox_item_id"
    t.string "method_id", null: false
    t.string "protocol_message_id", null: false
    t.bigint "report_document_id"
    t.string "result_code", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_connection_id"], name: "index_agent_control_report_receipts_on_agent_connection_id"
    t.index ["agent_task_run_id"], name: "index_agent_control_report_receipts_on_agent_task_run_id"
    t.index ["execution_runtime_connection_id"], name: "idx_on_execution_runtime_connection_id_a297467e5f"
    t.index ["installation_id", "protocol_message_id"], name: "idx_agent_control_report_receipts_protocol_message", unique: true
    t.index ["installation_id"], name: "index_agent_control_report_receipts_on_installation_id"
    t.index ["mailbox_item_id"], name: "index_agent_control_report_receipts_on_mailbox_item_id"
    t.index ["report_document_id"], name: "index_agent_control_report_receipts_on_report_document_id"
  end

  create_table "agent_definition_versions", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.bigint "canonical_config_schema_document_id", null: false
    t.bigint "conversation_override_schema_document_id", null: false
    t.datetime "created_at", null: false
    t.bigint "default_canonical_config_document_id", null: false
    t.string "definition_fingerprint", null: false
    t.bigint "installation_id", null: false
    t.bigint "profile_policy_document_id", null: false
    t.string "program_manifest_fingerprint", null: false
    t.string "prompt_pack_fingerprint", null: false
    t.string "prompt_pack_ref", null: false
    t.bigint "protocol_methods_document_id", null: false
    t.string "protocol_version", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.bigint "reflected_surface_document_id", null: false
    t.string "sdk_version", null: false
    t.bigint "tool_contract_document_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["agent_id", "definition_fingerprint"], name: "idx_agent_definition_versions_agent_fingerprint", unique: true
    t.index ["agent_id", "version"], name: "idx_agent_definition_versions_agent_version", unique: true
    t.index ["agent_id"], name: "index_agent_definition_versions_on_agent_id"
    t.index ["canonical_config_schema_document_id"], name: "idx_on_canonical_config_schema_document_id_be02eea8de"
    t.index ["conversation_override_schema_document_id"], name: "idx_on_conversation_override_schema_document_id_2b5847b4eb"
    t.index ["default_canonical_config_document_id"], name: "idx_on_default_canonical_config_document_id_81a3b00796"
    t.index ["installation_id"], name: "index_agent_definition_versions_on_installation_id"
    t.index ["profile_policy_document_id"], name: "index_agent_definition_versions_on_profile_policy_document_id"
    t.index ["protocol_methods_document_id"], name: "idx_on_protocol_methods_document_id_6c0cdfb44d"
    t.index ["public_id"], name: "index_agent_definition_versions_on_public_id", unique: true
    t.index ["reflected_surface_document_id"], name: "idx_on_reflected_surface_document_id_86042215e8"
    t.index ["tool_contract_document_id"], name: "index_agent_definition_versions_on_tool_contract_document_id"
  end

  create_table "agent_task_progress_entries", force: :cascade do |t|
    t.bigint "agent_task_run_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "details_payload", default: {}, null: false
    t.string "entry_kind", null: false
    t.bigint "installation_id", null: false
    t.datetime "occurred_at", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.integer "sequence", null: false
    t.bigint "subagent_connection_id"
    t.string "summary", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_task_run_id", "sequence"], name: "idx_agent_task_progress_entries_task_sequence", unique: true
    t.index ["agent_task_run_id"], name: "index_agent_task_progress_entries_on_agent_task_run_id"
    t.index ["installation_id"], name: "index_agent_task_progress_entries_on_installation_id"
    t.index ["public_id"], name: "index_agent_task_progress_entries_on_public_id", unique: true
    t.index ["subagent_connection_id"], name: "index_agent_task_progress_entries_on_subagent_connection_id"
  end

  create_table "agent_task_runs", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.integer "attempt_no", default: 1, null: false
    t.string "blocked_summary"
    t.datetime "close_acknowledged_at"
    t.datetime "close_force_deadline_at"
    t.datetime "close_grace_deadline_at"
    t.string "close_outcome_kind"
    t.jsonb "close_outcome_payload", default: {}, null: false
    t.string "close_reason_kind"
    t.datetime "close_requested_at"
    t.string "close_state", default: "open", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "current_focus_summary"
    t.integer "expected_duration_seconds"
    t.datetime "finished_at"
    t.string "focus_kind", default: "general", null: false
    t.bigint "holder_agent_connection_id"
    t.bigint "installation_id", null: false
    t.string "kind", null: false
    t.datetime "last_progress_at"
    t.string "lifecycle_state", default: "queued", null: false
    t.string "logical_work_id", null: false
    t.string "next_step_hint"
    t.bigint "origin_turn_id"
    t.jsonb "progress_payload", default: {}, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "recent_progress_summary"
    t.string "request_summary"
    t.datetime "started_at"
    t.bigint "subagent_connection_id"
    t.jsonb "supervision_payload", default: {}, null: false
    t.integer "supervision_sequence", default: 0, null: false
    t.string "supervision_state", default: "queued", null: false
    t.jsonb "task_payload", default: {}, null: false
    t.jsonb "terminal_payload", default: {}, null: false
    t.bigint "turn_id", null: false
    t.datetime "updated_at", null: false
    t.string "waiting_summary"
    t.bigint "workflow_node_id", null: false
    t.bigint "workflow_run_id", null: false
    t.index ["agent_id"], name: "index_agent_task_runs_on_agent_id"
    t.index ["conversation_id"], name: "index_agent_task_runs_on_conversation_id"
    t.index ["holder_agent_connection_id"], name: "index_agent_task_runs_on_holder_agent_connection_id"
    t.index ["installation_id"], name: "index_agent_task_runs_on_installation_id"
    t.index ["origin_turn_id"], name: "index_agent_task_runs_on_origin_turn_id"
    t.index ["public_id"], name: "index_agent_task_runs_on_public_id", unique: true
    t.index ["subagent_connection_id"], name: "index_agent_task_runs_on_subagent_connection_id"
    t.index ["turn_id"], name: "index_agent_task_runs_on_turn_id"
    t.index ["workflow_node_id"], name: "index_agent_task_runs_on_workflow_node_id"
    t.index ["workflow_run_id", "logical_work_id", "attempt_no"], name: "idx_agent_task_runs_work_attempt", unique: true
    t.index ["workflow_run_id"], name: "index_agent_task_runs_on_workflow_run_id"
  end

  create_table "agents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "default_execution_runtime_id"
    t.string "display_name", null: false
    t.bigint "installation_id", null: false
    t.string "key", null: false
    t.string "lifecycle_state", default: "active", null: false
    t.bigint "owner_user_id"
    t.string "provisioning_origin", default: "system", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.bigint "published_agent_definition_version_id"
    t.datetime "updated_at", null: false
    t.string "visibility", default: "public", null: false
    t.index ["default_execution_runtime_id"], name: "index_agents_on_default_execution_runtime_id"
    t.index ["installation_id", "key"], name: "index_agents_on_installation_id_and_key", unique: true
    t.index ["installation_id", "provisioning_origin"], name: "index_agents_on_installation_id_and_provisioning_origin"
    t.index ["installation_id", "visibility"], name: "index_agents_on_installation_id_and_visibility"
    t.index ["installation_id"], name: "index_agents_on_installation_id"
    t.index ["owner_user_id"], name: "index_agents_on_owner_user_id"
    t.index ["public_id"], name: "index_agents_on_public_id", unique: true
    t.index ["published_agent_definition_version_id"], name: "index_agents_on_published_agent_definition_version_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "subject_id"
    t.string "subject_type"
    t.datetime "updated_at", null: false
    t.index ["actor_type", "actor_id"], name: "index_audit_logs_on_actor"
    t.index ["installation_id", "action"], name: "index_audit_logs_on_installation_id_and_action"
    t.index ["installation_id"], name: "index_audit_logs_on_installation_id"
    t.index ["subject_type", "subject_id"], name: "index_audit_logs_on_subject"
  end

  create_table "canonical_variables", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "current", default: true, null: false
    t.bigint "installation_id", null: false
    t.string "key", null: false
    t.string "projection_policy", default: "silent", null: false
    t.string "scope", default: "workspace", null: false
    t.bigint "source_conversation_id"
    t.string "source_kind", null: false
    t.bigint "source_turn_id"
    t.bigint "source_workflow_run_id"
    t.datetime "superseded_at"
    t.bigint "superseded_by_id"
    t.jsonb "typed_value_payload", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.bigint "writer_id"
    t.string "writer_type"
    t.index ["installation_id"], name: "index_canonical_variables_on_installation_id"
    t.index ["source_conversation_id"], name: "index_canonical_variables_on_source_conversation_id"
    t.index ["source_turn_id"], name: "index_canonical_variables_on_source_turn_id"
    t.index ["source_workflow_run_id"], name: "index_canonical_variables_on_source_workflow_run_id"
    t.index ["superseded_by_id"], name: "index_canonical_variables_on_superseded_by_id"
    t.index ["workspace_id", "key"], name: "idx_canonical_variables_workspace_current", unique: true, where: "(((scope)::text = 'workspace'::text) AND (current = true))"
    t.index ["workspace_id"], name: "index_canonical_variables_on_workspace_id"
    t.index ["writer_type", "writer_id"], name: "idx_canonical_variables_writer"
    t.check_constraint "scope::text = 'workspace'::text", name: "chk_canonical_variables_workspace_scope_only"
  end

  create_table "command_runs", force: :cascade do |t|
    t.bigint "agent_task_run_id"
    t.string "command_line", null: false
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.integer "exit_status"
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", default: "starting", null: false
    t.jsonb "metadata", default: {}, null: false
    t.boolean "pty", default: false, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "started_at", null: false
    t.integer "timeout_seconds"
    t.bigint "tool_invocation_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workflow_node_id"
    t.index ["agent_task_run_id"], name: "index_command_runs_on_agent_task_run_id"
    t.index ["installation_id"], name: "index_command_runs_on_installation_id"
    t.index ["public_id"], name: "index_command_runs_on_public_id", unique: true
    t.index ["tool_invocation_id"], name: "index_command_runs_on_tool_invocation_id", unique: true
    t.index ["workflow_node_id"], name: "index_command_runs_on_workflow_node_id"
  end

  create_table "conversation_bundle_import_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "failure_payload", default: {}, null: false
    t.datetime "finished_at"
    t.bigint "imported_conversation_id"
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", default: "queued", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "queued_at"
    t.jsonb "request_payload", default: {}, null: false
    t.jsonb "result_payload", default: {}, null: false
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workspace_id", null: false
    t.index ["imported_conversation_id"], name: "idx_on_imported_conversation_id_8a4b454761"
    t.index ["installation_id"], name: "index_conversation_bundle_import_requests_on_installation_id"
    t.index ["public_id"], name: "index_conversation_bundle_import_requests_on_public_id", unique: true
    t.index ["user_id"], name: "index_conversation_bundle_import_requests_on_user_id"
    t.index ["workspace_id"], name: "index_conversation_bundle_import_requests_on_workspace_id"
  end

  create_table "conversation_capability_grants", force: :cascade do |t|
    t.string "capability", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "grant_state", default: "active", null: false
    t.string "grantee_kind", null: false
    t.string "grantee_public_id", null: false
    t.bigint "installation_id", null: false
    t.jsonb "policy_payload", default: {}, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.bigint "target_conversation_id", null: false
    t.datetime "updated_at", null: false
    t.index ["installation_id"], name: "index_conversation_capability_grants_on_installation_id"
    t.index ["public_id"], name: "index_conversation_capability_grants_on_public_id", unique: true
    t.index ["target_conversation_id", "grantee_kind", "grantee_public_id", "capability"], name: "idx_conversation_capability_grants_lookup"
    t.index ["target_conversation_id"], name: "index_conversation_capability_grants_on_target_conversation_id"
  end

  create_table "conversation_capability_policies", force: :cascade do |t|
    t.boolean "control_enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.boolean "detailed_progress_enabled", default: false, null: false
    t.bigint "installation_id", null: false
    t.jsonb "policy_payload", default: {}, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.boolean "side_chat_enabled", default: false, null: false
    t.boolean "supervision_enabled", default: false, null: false
    t.bigint "target_conversation_id", null: false
    t.datetime "updated_at", null: false
    t.index ["installation_id"], name: "index_conversation_capability_policies_on_installation_id"
    t.index ["public_id"], name: "index_conversation_capability_policies_on_public_id", unique: true
    t.index ["target_conversation_id"], name: "idx_conversation_capability_policies_target", unique: true
  end

  create_table "conversation_close_operations", force: :cascade do |t|
    t.datetime "completed_at"
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.string "intent_kind", null: false
    t.string "lifecycle_state", default: "requested", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "requested_at", null: false
    t.jsonb "summary_payload", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "idx_conversation_close_operations_unfinished", unique: true, where: "((lifecycle_state)::text <> ALL ((ARRAY['completed'::character varying, 'degraded'::character varying])::text[]))"
    t.index ["conversation_id"], name: "index_conversation_close_operations_on_conversation_id"
    t.index ["installation_id"], name: "index_conversation_close_operations_on_installation_id"
    t.index ["public_id"], name: "index_conversation_close_operations_on_public_id", unique: true
  end

  create_table "conversation_closures", force: :cascade do |t|
    t.bigint "ancestor_conversation_id", null: false
    t.datetime "created_at", null: false
    t.integer "depth", null: false
    t.bigint "descendant_conversation_id", null: false
    t.bigint "installation_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ancestor_conversation_id"], name: "index_conversation_closures_on_ancestor_conversation_id"
    t.index ["descendant_conversation_id"], name: "index_conversation_closures_on_descendant_conversation_id"
    t.index ["installation_id", "ancestor_conversation_id", "descendant_conversation_id"], name: "idx_conversation_closures_installation_ancestor_descendant", unique: true
    t.index ["installation_id"], name: "index_conversation_closures_on_installation_id"
  end

  create_table "conversation_control_requests", force: :cascade do |t|
    t.datetime "completed_at"
    t.bigint "conversation_supervision_session_id", null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", default: "queued", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "request_kind", null: false
    t.jsonb "request_payload", default: {}, null: false
    t.jsonb "result_payload", default: {}, null: false
    t.bigint "target_conversation_id", null: false
    t.string "target_kind", null: false
    t.string "target_public_id"
    t.datetime "updated_at", null: false
    t.index ["conversation_supervision_session_id"], name: "idx_on_conversation_supervision_session_id_38f140b9f0"
    t.index ["installation_id", "request_kind", "lifecycle_state", "target_conversation_id", "completed_at"], name: "idx_ccr_guidance_projection_conversation"
    t.index ["installation_id", "request_kind", "lifecycle_state", "target_public_id", "completed_at"], name: "idx_ccr_guidance_projection_subagent"
    t.index ["installation_id"], name: "index_conversation_control_requests_on_installation_id"
    t.index ["public_id"], name: "index_conversation_control_requests_on_public_id", unique: true
    t.index ["target_conversation_id"], name: "index_conversation_control_requests_on_target_conversation_id"
  end

  create_table "conversation_debug_export_requests", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.jsonb "failure_payload", default: {}, null: false
    t.datetime "finished_at"
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", default: "queued", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "queued_at"
    t.jsonb "request_payload", default: {}, null: false
    t.jsonb "result_payload", default: {}, null: false
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workspace_id", null: false
    t.index ["conversation_id"], name: "index_conversation_debug_export_requests_on_conversation_id"
    t.index ["installation_id"], name: "index_conversation_debug_export_requests_on_installation_id"
    t.index ["public_id"], name: "index_conversation_debug_export_requests_on_public_id", unique: true
    t.index ["user_id"], name: "index_conversation_debug_export_requests_on_user_id"
    t.index ["workspace_id"], name: "index_conversation_debug_export_requests_on_workspace_id"
  end

  create_table "conversation_diagnostics_snapshots", force: :cascade do |t|
    t.integer "active_turn_count", default: 0, null: false
    t.integer "attributed_user_estimated_cost_event_count", default: 0, null: false
    t.integer "attributed_user_estimated_cost_missing_event_count", default: 0, null: false
    t.decimal "attributed_user_estimated_cost_total", precision: 12, scale: 6, default: "0.0", null: false
    t.integer "attributed_user_input_tokens_total", default: 0, null: false
    t.integer "attributed_user_output_tokens_total", default: 0, null: false
    t.integer "attributed_user_usage_event_count", default: 0, null: false
    t.integer "cached_input_tokens_total", default: 0, null: false
    t.integer "canceled_turn_count", default: 0, null: false
    t.integer "command_failure_count", default: 0, null: false
    t.integer "command_run_count", default: 0, null: false
    t.integer "completed_turn_count", default: 0, null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.integer "estimated_cost_event_count", default: 0, null: false
    t.integer "estimated_cost_missing_event_count", default: 0, null: false
    t.decimal "estimated_cost_total", precision: 12, scale: 6, default: "0.0", null: false
    t.integer "failed_turn_count", default: 0, null: false
    t.integer "input_tokens_total", default: 0, null: false
    t.integer "input_variant_count", default: 0, null: false
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "most_expensive_turn_id"
    t.bigint "most_rounds_turn_id"
    t.integer "output_tokens_total", default: 0, null: false
    t.integer "output_variant_count", default: 0, null: false
    t.integer "process_failure_count", default: 0, null: false
    t.integer "process_run_count", default: 0, null: false
    t.integer "prompt_cache_available_event_count", default: 0, null: false
    t.integer "prompt_cache_unknown_event_count", default: 0, null: false
    t.integer "prompt_cache_unsupported_event_count", default: 0, null: false
    t.integer "provider_round_count", default: 0, null: false
    t.integer "resume_attempt_count", default: 0, null: false
    t.integer "retry_attempt_count", default: 0, null: false
    t.integer "subagent_connection_count", default: 0, null: false
    t.integer "tool_call_count", default: 0, null: false
    t.integer "tool_failure_count", default: 0, null: false
    t.integer "turn_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "usage_event_count", default: 0, null: false
    t.index ["conversation_id"], name: "index_conversation_diagnostics_snapshots_on_conversation_id", unique: true
    t.index ["installation_id"], name: "index_conversation_diagnostics_snapshots_on_installation_id"
    t.index ["most_expensive_turn_id"], name: "idx_on_most_expensive_turn_id_9cbc3f90b7"
    t.index ["most_rounds_turn_id"], name: "idx_on_most_rounds_turn_id_0ab63b2e39"
  end

  create_table "conversation_events", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "event_kind", null: false
    t.bigint "installation_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.integer "projection_sequence", null: false
    t.bigint "source_id"
    t.string "source_type"
    t.string "stream_key"
    t.integer "stream_revision"
    t.bigint "turn_id"
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "projection_sequence"], name: "idx_conversation_events_projection_sequence", unique: true
    t.index ["conversation_id", "stream_key", "stream_revision"], name: "idx_conversation_events_stream_revision", unique: true, where: "(stream_key IS NOT NULL)"
    t.index ["conversation_id"], name: "index_conversation_events_on_conversation_id"
    t.index ["installation_id"], name: "index_conversation_events_on_installation_id"
    t.index ["source_type", "source_id"], name: "idx_conversation_events_source"
    t.index ["turn_id"], name: "index_conversation_events_on_turn_id"
  end

  create_table "conversation_export_requests", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.jsonb "failure_payload", default: {}, null: false
    t.datetime "finished_at"
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", default: "queued", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "queued_at"
    t.jsonb "request_payload", default: {}, null: false
    t.jsonb "result_payload", default: {}, null: false
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workspace_id", null: false
    t.index ["conversation_id"], name: "index_conversation_export_requests_on_conversation_id"
    t.index ["installation_id"], name: "index_conversation_export_requests_on_installation_id"
    t.index ["public_id"], name: "index_conversation_export_requests_on_public_id", unique: true
    t.index ["user_id"], name: "index_conversation_export_requests_on_user_id"
    t.index ["workspace_id"], name: "index_conversation_export_requests_on_workspace_id"
  end

  create_table "conversation_imports", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.string "kind", null: false
    t.bigint "source_conversation_id"
    t.bigint "source_message_id"
    t.bigint "summary_segment_id"
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "kind"], name: "index_conversation_imports_on_conversation_id_and_kind"
    t.index ["conversation_id"], name: "index_conversation_imports_on_conversation_id"
    t.index ["installation_id"], name: "index_conversation_imports_on_installation_id"
    t.index ["source_conversation_id"], name: "index_conversation_imports_on_source_conversation_id"
    t.index ["source_message_id"], name: "index_conversation_imports_on_source_message_id"
    t.index ["summary_segment_id"], name: "index_conversation_imports_on_summary_segment_id"
  end

  create_table "conversation_message_visibilities", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.boolean "excluded_from_context", default: false, null: false
    t.boolean "hidden", default: false, null: false
    t.bigint "installation_id", null: false
    t.bigint "message_id", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "message_id"], name: "idx_message_visibilities_conversation_message", unique: true
    t.index ["conversation_id"], name: "index_conversation_message_visibilities_on_conversation_id"
    t.index ["installation_id"], name: "index_conversation_message_visibilities_on_installation_id"
    t.index ["message_id"], name: "index_conversation_message_visibilities_on_message_id"
  end

  create_table "conversation_summary_segments", force: :cascade do |t|
    t.text "content", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "end_message_id", null: false
    t.bigint "installation_id", null: false
    t.bigint "start_message_id", null: false
    t.bigint "superseded_by_id"
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_conversation_summary_segments_on_conversation_id"
    t.index ["end_message_id"], name: "index_conversation_summary_segments_on_end_message_id"
    t.index ["installation_id"], name: "index_conversation_summary_segments_on_installation_id"
    t.index ["start_message_id"], name: "index_conversation_summary_segments_on_start_message_id"
    t.index ["superseded_by_id"], name: "index_conversation_summary_segments_on_superseded_by_id"
  end

  create_table "conversation_supervision_feed_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "details_payload", default: {}, null: false
    t.string "event_kind", null: false
    t.bigint "installation_id", null: false
    t.datetime "occurred_at", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.integer "sequence", null: false
    t.string "summary", null: false
    t.bigint "target_conversation_id", null: false
    t.bigint "target_turn_id"
    t.datetime "updated_at", null: false
    t.index ["installation_id"], name: "index_conversation_supervision_feed_entries_on_installation_id"
    t.index ["public_id"], name: "index_conversation_supervision_feed_entries_on_public_id", unique: true
    t.index ["target_conversation_id", "sequence"], name: "idx_conversation_supervision_feed_entries_sequence", unique: true
    t.index ["target_conversation_id", "target_turn_id", "sequence"], name: "idx_conversation_supervision_feed_entries_turn_sequence"
    t.index ["target_conversation_id"], name: "idx_on_target_conversation_id_5b93de306a"
    t.index ["target_turn_id"], name: "index_conversation_supervision_feed_entries_on_target_turn_id"
  end

  create_table "conversation_supervision_messages", force: :cascade do |t|
    t.text "content", null: false
    t.bigint "conversation_supervision_session_id", null: false
    t.bigint "conversation_supervision_snapshot_id", null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "role", null: false
    t.bigint "target_conversation_id", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_supervision_session_id", "created_at"], name: "idx_conversation_supervision_messages_session_created"
    t.index ["conversation_supervision_session_id"], name: "idx_on_conversation_supervision_session_id_e90028369c"
    t.index ["conversation_supervision_snapshot_id"], name: "idx_on_conversation_supervision_snapshot_id_3bc399b19b"
    t.index ["installation_id"], name: "index_conversation_supervision_messages_on_installation_id"
    t.index ["public_id"], name: "index_conversation_supervision_messages_on_public_id", unique: true
    t.index ["target_conversation_id"], name: "idx_on_target_conversation_id_640b61cd24"
  end

  create_table "conversation_supervision_sessions", force: :cascade do |t|
    t.jsonb "capability_policy_snapshot", default: {}, null: false
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.bigint "initiator_id", null: false
    t.string "initiator_type", null: false
    t.bigint "installation_id", null: false
    t.datetime "last_snapshot_at"
    t.string "lifecycle_state", default: "open", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "responder_strategy", default: "summary_model", null: false
    t.bigint "target_conversation_id", null: false
    t.datetime "updated_at", null: false
    t.index ["initiator_type", "initiator_id"], name: "index_conversation_supervision_sessions_on_initiator"
    t.index ["installation_id"], name: "index_conversation_supervision_sessions_on_installation_id"
    t.index ["lifecycle_state", "closed_at"], name: "idx_css_lifecycle_closed_at"
    t.index ["public_id"], name: "index_conversation_supervision_sessions_on_public_id", unique: true
    t.index ["target_conversation_id", "created_at"], name: "idx_conversation_supervision_sessions_target_created"
    t.index ["target_conversation_id"], name: "idx_on_target_conversation_id_894b853f4a"
  end

  create_table "conversation_supervision_snapshots", force: :cascade do |t|
    t.jsonb "active_subagent_connection_public_ids", default: [], null: false
    t.string "active_workflow_node_public_id"
    t.string "active_workflow_run_public_id"
    t.string "anchor_turn_public_id"
    t.integer "anchor_turn_sequence_snapshot"
    t.jsonb "bundle_payload", default: {}, null: false
    t.string "conversation_capability_policy_public_id"
    t.integer "conversation_event_projection_sequence_snapshot"
    t.bigint "conversation_supervision_session_id", null: false
    t.string "conversation_supervision_state_public_id"
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.jsonb "machine_status_payload", default: {}, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.bigint "target_conversation_id", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_supervision_session_id", "created_at"], name: "idx_conversation_supervision_snapshots_session_created"
    t.index ["conversation_supervision_session_id"], name: "idx_on_conversation_supervision_session_id_822fd45ddc"
    t.index ["installation_id"], name: "index_conversation_supervision_snapshots_on_installation_id"
    t.index ["public_id"], name: "index_conversation_supervision_snapshots_on_public_id", unique: true
    t.index ["target_conversation_id"], name: "idx_on_target_conversation_id_58845791db"
  end

  create_table "conversation_supervision_states", force: :cascade do |t|
    t.integer "active_plan_item_count", default: 0, null: false
    t.integer "active_subagent_count", default: 0, null: false
    t.string "blocked_summary"
    t.jsonb "board_badges", default: [], null: false
    t.string "board_lane", default: "idle", null: false
    t.integer "completed_plan_item_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "current_focus_summary"
    t.string "current_owner_kind"
    t.string "current_owner_public_id"
    t.bigint "installation_id", null: false
    t.datetime "lane_changed_at"
    t.datetime "last_progress_at"
    t.datetime "last_terminal_at"
    t.string "last_terminal_state"
    t.string "next_step_hint"
    t.string "overall_state", default: "idle", null: false
    t.integer "projection_version", default: 0, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "recent_progress_summary"
    t.string "request_summary"
    t.datetime "retry_due_at"
    t.jsonb "status_payload", default: {}, null: false
    t.bigint "target_conversation_id", null: false
    t.datetime "updated_at", null: false
    t.string "waiting_summary"
    t.index ["installation_id"], name: "index_conversation_supervision_states_on_installation_id"
    t.index ["public_id"], name: "index_conversation_supervision_states_on_public_id", unique: true
    t.index ["target_conversation_id"], name: "idx_conversation_supervision_states_target", unique: true
  end

  create_table "conversations", force: :cascade do |t|
    t.string "addressability", default: "owner_addressable", null: false
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "deletion_state", default: "retained", null: false
    t.string "during_generation_input_policy", default: "queue", null: false
    t.string "enabled_feature_ids", default: [], null: false, array: true
    t.bigint "historical_anchor_message_id"
    t.bigint "installation_id", null: false
    t.string "interactive_selector_mode", default: "auto", null: false
    t.string "interactive_selector_model_ref"
    t.string "interactive_selector_provider_handle"
    t.string "kind", null: false
    t.string "lifecycle_state", null: false
    t.string "override_last_schema_fingerprint"
    t.jsonb "override_payload", default: {}, null: false
    t.jsonb "override_reconciliation_report", default: {}, null: false
    t.datetime "override_updated_at"
    t.bigint "parent_conversation_id"
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "purpose", null: false
    t.text "summary"
    t.string "summary_lock_state", default: "unlocked", null: false
    t.string "summary_source", default: "none", null: false
    t.datetime "summary_updated_at"
    t.text "title"
    t.string "title_lock_state", default: "unlocked", null: false
    t.string "title_source", default: "none", null: false
    t.datetime "title_updated_at"
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["agent_id", "lifecycle_state"], name: "idx_conversations_agent_lifecycle"
    t.index ["agent_id"], name: "index_conversations_on_agent_id"
    t.index ["installation_id"], name: "index_conversations_on_installation_id"
    t.index ["parent_conversation_id"], name: "index_conversations_on_parent_conversation_id"
    t.index ["public_id"], name: "index_conversations_on_public_id", unique: true
    t.index ["workspace_id", "purpose", "lifecycle_state"], name: "idx_conversations_workspace_purpose_lifecycle"
    t.index ["workspace_id"], name: "index_conversations_on_workspace_id"
    t.check_constraint "deletion_state::text = 'retained'::text AND deleted_at IS NULL OR (deletion_state::text = ANY (ARRAY['pending_delete'::character varying, 'deleted'::character varying]::text[])) AND deleted_at IS NOT NULL", name: "chk_conversations_deleted_at_consistency"
    t.check_constraint "deletion_state::text = ANY (ARRAY['retained'::character varying, 'pending_delete'::character varying, 'deleted'::character varying]::text[])", name: "chk_conversations_deletion_state"
    t.check_constraint "during_generation_input_policy::text = ANY (ARRAY['reject'::character varying, 'restart'::character varying, 'queue'::character varying]::text[])", name: "chk_conversations_during_generation_input_policy"
    t.check_constraint "summary_lock_state::text = ANY (ARRAY['unlocked'::character varying, 'user_locked'::character varying]::text[])", name: "chk_conversations_summary_lock_state"
    t.check_constraint "summary_source::text = ANY (ARRAY['none'::character varying, 'bootstrap'::character varying, 'generated'::character varying, 'agent'::character varying, 'user'::character varying]::text[])", name: "chk_conversations_summary_source"
    t.check_constraint "title_lock_state::text = ANY (ARRAY['unlocked'::character varying, 'user_locked'::character varying]::text[])", name: "chk_conversations_title_lock_state"
    t.check_constraint "title_source::text = ANY (ARRAY['none'::character varying, 'bootstrap'::character varying, 'generated'::character varying, 'agent'::character varying, 'user'::character varying]::text[])", name: "chk_conversations_title_source"
  end

  create_table "execution_capability_snapshots", force: :cascade do |t|
    t.bigint "agent_definition_version_id", null: false
    t.datetime "created_at", null: false
    t.string "fingerprint", null: false
    t.bigint "installation_id", null: false
    t.bigint "owner_conversation_id"
    t.bigint "parent_subagent_connection_id"
    t.string "profile_key", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.boolean "subagent", default: false, null: false
    t.bigint "subagent_connection_id"
    t.integer "subagent_depth"
    t.jsonb "subagent_policy_snapshot", default: {}, null: false
    t.bigint "tool_surface_document_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_definition_version_id"], name: "idx_on_agent_definition_version_id_445401aa82"
    t.index ["installation_id", "fingerprint"], name: "idx_execution_capability_snapshots_fingerprint", unique: true
    t.index ["installation_id"], name: "index_execution_capability_snapshots_on_installation_id"
    t.index ["owner_conversation_id"], name: "index_execution_capability_snapshots_on_owner_conversation_id"
    t.index ["parent_subagent_connection_id"], name: "idx_on_parent_subagent_connection_id_5d3d51c021"
    t.index ["public_id"], name: "index_execution_capability_snapshots_on_public_id", unique: true
    t.index ["subagent_connection_id"], name: "index_execution_capability_snapshots_on_subagent_connection_id"
    t.index ["tool_surface_document_id"], name: "idx_on_tool_surface_document_id_d26e5f2342"
  end

  create_table "execution_context_snapshots", force: :cascade do |t|
    t.jsonb "attachment_refs", default: [], null: false
    t.datetime "created_at", null: false
    t.string "fingerprint", null: false
    t.jsonb "import_refs", default: [], null: false
    t.bigint "installation_id", null: false
    t.jsonb "message_refs", default: [], null: false
    t.string "projection_fingerprint", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "updated_at", null: false
    t.index ["installation_id", "fingerprint"], name: "idx_execution_context_snapshots_fingerprint", unique: true
    t.index ["installation_id"], name: "index_execution_context_snapshots_on_installation_id"
    t.index ["public_id"], name: "index_execution_context_snapshots_on_public_id", unique: true
  end

  create_table "execution_contracts", force: :cascade do |t|
    t.bigint "agent_definition_version_id", null: false
    t.jsonb "attachment_diagnostics", default: [], null: false
    t.jsonb "attachment_manifest", default: [], null: false
    t.datetime "created_at", null: false
    t.bigint "execution_capability_snapshot_id", null: false
    t.bigint "execution_context_snapshot_id", null: false
    t.bigint "execution_runtime_id"
    t.bigint "execution_runtime_version_id"
    t.bigint "installation_id", null: false
    t.jsonb "model_input_attachments", default: [], null: false
    t.jsonb "provider_context", default: {}, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.bigint "selected_input_message_id"
    t.bigint "selected_output_message_id"
    t.bigint "turn_id", null: false
    t.jsonb "turn_origin", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["agent_definition_version_id"], name: "index_execution_contracts_on_agent_definition_version_id"
    t.index ["execution_capability_snapshot_id"], name: "index_execution_contracts_on_execution_capability_snapshot_id"
    t.index ["execution_context_snapshot_id"], name: "index_execution_contracts_on_execution_context_snapshot_id"
    t.index ["execution_runtime_id"], name: "index_execution_contracts_on_execution_runtime_id"
    t.index ["execution_runtime_version_id"], name: "index_execution_contracts_on_execution_runtime_version_id"
    t.index ["installation_id"], name: "index_execution_contracts_on_installation_id"
    t.index ["public_id"], name: "index_execution_contracts_on_public_id", unique: true
    t.index ["selected_input_message_id"], name: "index_execution_contracts_on_selected_input_message_id"
    t.index ["selected_output_message_id"], name: "index_execution_contracts_on_selected_output_message_id"
    t.index ["turn_id"], name: "index_execution_contracts_on_turn_id", unique: true
  end

  create_table "execution_leases", force: :cascade do |t|
    t.datetime "acquired_at", null: false
    t.datetime "created_at", null: false
    t.integer "heartbeat_timeout_seconds", null: false
    t.string "holder_key", null: false
    t.bigint "installation_id", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "leased_resource_id", null: false
    t.string "leased_resource_type", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "release_reason"
    t.datetime "released_at"
    t.datetime "updated_at", null: false
    t.bigint "workflow_node_id", null: false
    t.bigint "workflow_run_id", null: false
    t.index ["holder_key", "released_at"], name: "idx_execution_leases_holder_released"
    t.index ["installation_id"], name: "index_execution_leases_on_installation_id"
    t.index ["leased_resource_type", "leased_resource_id"], name: "idx_execution_leases_active_resource", unique: true, where: "(released_at IS NULL)"
    t.index ["leased_resource_type", "leased_resource_id"], name: "idx_execution_leases_resource"
    t.index ["workflow_node_id"], name: "index_execution_leases_on_workflow_node_id"
    t.index ["workflow_run_id", "released_at"], name: "idx_execution_leases_run_released"
    t.index ["workflow_run_id"], name: "index_execution_leases_on_workflow_run_id"
  end

  create_table "execution_profile_facts", force: :cascade do |t|
    t.string "api_model"
    t.bigint "conversation_id"
    t.integer "count_value"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "error_class"
    t.text "error_message"
    t.string "fact_key", null: false
    t.string "fact_kind", null: false
    t.bigint "human_interaction_request_id"
    t.bigint "installation_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "model_ref"
    t.datetime "occurred_at", null: false
    t.bigint "process_run_id"
    t.string "provider_handle"
    t.string "provider_request_id"
    t.integer "recommended_compaction_threshold"
    t.bigint "subagent_connection_id"
    t.boolean "success"
    t.boolean "threshold_crossed"
    t.integer "total_tokens"
    t.bigint "turn_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "wire_api"
    t.string "workflow_node_key"
    t.bigint "workspace_id"
    t.index ["installation_id", "fact_kind", "fact_key"], name: "idx_execution_profile_facts_installation_kind_key"
    t.index ["installation_id", "occurred_at"], name: "idx_on_installation_id_occurred_at_361e402309"
    t.index ["installation_id"], name: "index_execution_profile_facts_on_installation_id"
    t.index ["user_id"], name: "index_execution_profile_facts_on_user_id"
    t.index ["workspace_id"], name: "index_execution_profile_facts_on_workspace_id"
  end

  create_table "execution_runtime_connections", force: :cascade do |t|
    t.string "connection_credential_digest", null: false
    t.string "connection_token_digest", null: false
    t.datetime "created_at", null: false
    t.jsonb "endpoint_metadata", default: {}, null: false
    t.bigint "execution_runtime_id", null: false
    t.bigint "execution_runtime_version_id", null: false
    t.bigint "installation_id", null: false
    t.datetime "last_heartbeat_at"
    t.string "lifecycle_state", default: "active", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "updated_at", null: false
    t.index ["connection_credential_digest"], name: "idx_on_connection_credential_digest_33f96fe027", unique: true
    t.index ["connection_token_digest"], name: "index_execution_runtime_connections_on_connection_token_digest", unique: true
    t.index ["execution_runtime_id"], name: "idx_execution_runtime_connections_runtime_active", unique: true, where: "((lifecycle_state)::text = 'active'::text)"
    t.index ["execution_runtime_id"], name: "index_execution_runtime_connections_on_execution_runtime_id"
    t.index ["execution_runtime_version_id"], name: "idx_on_execution_runtime_version_id_b80affb52f"
    t.index ["installation_id"], name: "index_execution_runtime_connections_on_installation_id"
    t.index ["public_id"], name: "index_execution_runtime_connections_on_public_id", unique: true
  end

  create_table "execution_runtime_versions", force: :cascade do |t|
    t.bigint "capability_payload_document_id", null: false
    t.string "content_fingerprint", null: false
    t.datetime "created_at", null: false
    t.string "execution_runtime_fingerprint", null: false
    t.bigint "execution_runtime_id", null: false
    t.bigint "installation_id", null: false
    t.string "kind", null: false
    t.string "protocol_version", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.bigint "reflected_host_metadata_document_id"
    t.string "sdk_version", null: false
    t.bigint "tool_catalog_document_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["capability_payload_document_id"], name: "idx_on_capability_payload_document_id_b0761bd979"
    t.index ["execution_runtime_id", "content_fingerprint"], name: "idx_execution_runtime_versions_runtime_fingerprint", unique: true
    t.index ["execution_runtime_id", "version"], name: "idx_execution_runtime_versions_runtime_version", unique: true
    t.index ["execution_runtime_id"], name: "index_execution_runtime_versions_on_execution_runtime_id"
    t.index ["installation_id"], name: "index_execution_runtime_versions_on_installation_id"
    t.index ["public_id"], name: "index_execution_runtime_versions_on_public_id", unique: true
    t.index ["reflected_host_metadata_document_id"], name: "idx_on_reflected_host_metadata_document_id_80ef5d7d5c"
    t.index ["tool_catalog_document_id"], name: "index_execution_runtime_versions_on_tool_catalog_document_id"
  end

  create_table "execution_runtimes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.bigint "installation_id", null: false
    t.string "kind", default: "local", null: false
    t.string "lifecycle_state", default: "active", null: false
    t.bigint "owner_user_id"
    t.string "provisioning_origin", default: "system", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.bigint "published_execution_runtime_version_id"
    t.datetime "updated_at", null: false
    t.string "visibility", default: "public", null: false
    t.index ["installation_id", "kind"], name: "index_execution_runtimes_on_installation_id_and_kind"
    t.index ["installation_id", "provisioning_origin"], name: "idx_on_installation_id_provisioning_origin_3ec0756f3e"
    t.index ["installation_id", "visibility"], name: "index_execution_runtimes_on_installation_id_and_visibility"
    t.index ["installation_id"], name: "index_execution_runtimes_on_installation_id"
    t.index ["owner_user_id"], name: "index_execution_runtimes_on_owner_user_id"
    t.index ["public_id"], name: "index_execution_runtimes_on_public_id", unique: true
    t.index ["published_execution_runtime_version_id"], name: "idx_on_published_execution_runtime_version_id_33547d051c"
  end

  create_table "human_interaction_requests", force: :cascade do |t|
    t.boolean "blocking", default: true, null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", default: "open", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.jsonb "request_payload", default: {}, null: false
    t.string "resolution_kind"
    t.datetime "resolved_at"
    t.jsonb "result_payload", default: {}, null: false
    t.bigint "turn_id", null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.bigint "workflow_node_id", null: false
    t.bigint "workflow_run_id", null: false
    t.index ["conversation_id", "lifecycle_state"], name: "idx_human_requests_conversation_lifecycle"
    t.index ["conversation_id"], name: "index_human_interaction_requests_on_conversation_id"
    t.index ["installation_id"], name: "index_human_interaction_requests_on_installation_id"
    t.index ["public_id"], name: "index_human_interaction_requests_on_public_id", unique: true
    t.index ["turn_id"], name: "index_human_interaction_requests_on_turn_id"
    t.index ["type", "lifecycle_state"], name: "idx_human_requests_type_lifecycle"
    t.index ["workflow_node_id"], name: "index_human_interaction_requests_on_workflow_node_id"
    t.index ["workflow_run_id", "lifecycle_state"], name: "idx_human_requests_workflow_lifecycle"
    t.index ["workflow_run_id"], name: "index_human_interaction_requests_on_workflow_run_id"
  end

  create_table "identities", force: :cascade do |t|
    t.jsonb "auth_metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "disabled_at"
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_identities_on_email", unique: true
  end

  create_table "implementation_sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "source_kind", null: false
    t.string "source_ref", null: false
    t.datetime "updated_at", null: false
    t.index ["installation_id", "source_kind", "source_ref"], name: "idx_implementation_sources_identity", unique: true
    t.index ["installation_id"], name: "index_implementation_sources_on_installation_id"
    t.index ["public_id"], name: "index_implementation_sources_on_public_id", unique: true
  end

  create_table "installations", force: :cascade do |t|
    t.string "bootstrap_state", default: "pending", null: false
    t.datetime "created_at", null: false
    t.jsonb "global_settings", default: {}, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "invitations", force: :cascade do |t|
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.bigint "installation_id", null: false
    t.bigint "inviter_id", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_invitations_on_email"
    t.index ["installation_id"], name: "index_invitations_on_installation_id"
    t.index ["inviter_id"], name: "index_invitations_on_inviter_id"
    t.index ["public_id"], name: "index_invitations_on_public_id", unique: true
    t.index ["token_digest"], name: "index_invitations_on_token_digest", unique: true
  end

  create_table "json_documents", force: :cascade do |t|
    t.integer "content_bytesize", null: false
    t.string "content_sha256", null: false
    t.datetime "created_at", null: false
    t.string "document_kind", null: false
    t.bigint "installation_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "updated_at", null: false
    t.index ["installation_id", "document_kind", "content_sha256"], name: "idx_json_documents_identity", unique: true
    t.index ["installation_id"], name: "index_json_documents_on_installation_id"
    t.index ["public_id"], name: "index_json_documents_on_public_id", unique: true
    t.check_constraint "content_bytesize >= 0 AND content_bytesize <= 8388608", name: "chk_json_documents_content_bytesize"
  end

  create_table "lineage_store_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "entry_kind", null: false
    t.string "key", null: false
    t.bigint "lineage_store_snapshot_id", null: false
    t.bigint "lineage_store_value_id"
    t.datetime "updated_at", null: false
    t.integer "value_bytesize"
    t.string "value_type"
    t.index ["lineage_store_snapshot_id", "key"], name: "idx_lineage_store_entries_snapshot_key", unique: true
    t.index ["lineage_store_snapshot_id"], name: "index_lineage_store_entries_on_lineage_store_snapshot_id"
    t.index ["lineage_store_value_id"], name: "index_lineage_store_entries_on_lineage_store_value_id"
    t.check_constraint "entry_kind::text = 'set'::text AND lineage_store_value_id IS NOT NULL AND value_type IS NOT NULL AND value_bytesize IS NOT NULL AND value_bytesize >= 0 AND value_bytesize <= 2097152 OR entry_kind::text = 'tombstone'::text AND lineage_store_value_id IS NULL AND value_type IS NULL AND value_bytesize IS NULL", name: "chk_lineage_store_entries_value_shape"
    t.check_constraint "entry_kind::text = ANY (ARRAY['set'::character varying, 'tombstone'::character varying]::text[])", name: "chk_lineage_store_entries_kind"
    t.check_constraint "octet_length(key::text) >= 1 AND octet_length(key::text) <= 128", name: "chk_lineage_store_entries_key_bytes"
  end

  create_table "lineage_store_references", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "lineage_store_snapshot_id", null: false
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.datetime "updated_at", null: false
    t.index ["lineage_store_snapshot_id"], name: "index_lineage_store_references_on_lineage_store_snapshot_id"
    t.index ["owner_type", "owner_id"], name: "idx_lineage_store_references_owner", unique: true
  end

  create_table "lineage_store_snapshots", force: :cascade do |t|
    t.bigint "base_snapshot_id"
    t.datetime "created_at", null: false
    t.integer "depth", null: false
    t.bigint "lineage_store_id", null: false
    t.string "snapshot_kind", null: false
    t.datetime "updated_at", null: false
    t.index ["base_snapshot_id"], name: "index_lineage_store_snapshots_on_base_snapshot_id"
    t.index ["lineage_store_id"], name: "index_lineage_store_snapshots_on_lineage_store_id"
    t.check_constraint "(snapshot_kind::text = ANY (ARRAY['root'::character varying, 'compaction'::character varying]::text[])) AND base_snapshot_id IS NULL AND depth = 0 OR snapshot_kind::text = 'write'::text AND base_snapshot_id IS NOT NULL AND depth >= 1", name: "chk_lineage_store_snapshots_shape"
    t.check_constraint "snapshot_kind::text = ANY (ARRAY['root'::character varying, 'write'::character varying, 'compaction'::character varying]::text[])", name: "chk_lineage_store_snapshots_kind"
  end

  create_table "lineage_store_values", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "payload_bytesize", null: false
    t.string "payload_sha256", null: false
    t.jsonb "typed_value_payload", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["payload_sha256"], name: "index_lineage_store_values_on_payload_sha256"
    t.check_constraint "payload_bytesize >= 0 AND payload_bytesize <= 2097152", name: "chk_lineage_store_values_payload_bytesize"
  end

  create_table "lineage_stores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.bigint "root_conversation_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["installation_id"], name: "index_lineage_stores_on_installation_id"
    t.index ["root_conversation_id"], name: "index_lineage_stores_on_root_conversation_id", unique: true
    t.index ["workspace_id"], name: "index_lineage_stores_on_workspace_id"
  end

  create_table "message_attachments", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.bigint "message_id", null: false
    t.bigint "origin_attachment_id"
    t.bigint "origin_message_id"
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_message_attachments_on_conversation_id"
    t.index ["installation_id"], name: "index_message_attachments_on_installation_id"
    t.index ["message_id"], name: "index_message_attachments_on_message_id"
    t.index ["origin_attachment_id"], name: "index_message_attachments_on_origin_attachment_id"
    t.index ["origin_message_id"], name: "index_message_attachments_on_origin_message_id"
    t.index ["public_id"], name: "index_message_attachments_on_public_id", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.text "content", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "role", null: false
    t.string "slot", null: false
    t.bigint "source_input_message_id"
    t.bigint "turn_id", null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.integer "variant_index", default: 0, null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["installation_id"], name: "index_messages_on_installation_id"
    t.index ["public_id"], name: "index_messages_on_public_id", unique: true
    t.index ["source_input_message_id"], name: "index_messages_on_source_input_message_id"
    t.index ["turn_id", "slot", "variant_index"], name: "index_messages_on_turn_id_and_slot_and_variant_index", unique: true
    t.index ["turn_id"], name: "index_messages_on_turn_id"
  end

  create_table "pairing_sessions", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "agent_registered_at"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "installation_id", null: false
    t.datetime "issued_at", null: false
    t.datetime "last_used_at"
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "revoked_at"
    t.datetime "runtime_registered_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_pairing_sessions_on_agent_id"
    t.index ["installation_id", "agent_id", "expires_at"], name: "idx_pairing_sessions_installation_agent_expiry"
    t.index ["installation_id"], name: "index_pairing_sessions_on_installation_id"
    t.index ["public_id"], name: "index_pairing_sessions_on_public_id", unique: true
    t.index ["token_digest"], name: "index_pairing_sessions_on_token_digest", unique: true
  end

  create_table "process_runs", force: :cascade do |t|
    t.datetime "close_acknowledged_at"
    t.datetime "close_force_deadline_at"
    t.datetime "close_grace_deadline_at"
    t.string "close_outcome_kind"
    t.jsonb "close_outcome_payload", default: {}, null: false
    t.string "close_reason_kind"
    t.datetime "close_requested_at"
    t.string "close_state", default: "open", null: false
    t.string "command_line", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.bigint "execution_runtime_id", null: false
    t.integer "exit_status"
    t.string "idempotency_key"
    t.bigint "installation_id", null: false
    t.string "kind", null: false
    t.string "lifecycle_state", default: "running", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "origin_message_id"
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "started_at", null: false
    t.integer "timeout_seconds"
    t.bigint "turn_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workflow_node_id", null: false
    t.index ["conversation_id", "lifecycle_state"], name: "idx_process_runs_conversation_lifecycle"
    t.index ["conversation_id"], name: "index_process_runs_on_conversation_id"
    t.index ["execution_runtime_id", "lifecycle_state"], name: "idx_process_runs_executor_lifecycle"
    t.index ["execution_runtime_id"], name: "index_process_runs_on_execution_runtime_id"
    t.index ["installation_id"], name: "index_process_runs_on_installation_id"
    t.index ["origin_message_id"], name: "index_process_runs_on_origin_message_id"
    t.index ["public_id"], name: "index_process_runs_on_public_id", unique: true
    t.index ["turn_id"], name: "index_process_runs_on_turn_id"
    t.index ["workflow_node_id", "idempotency_key"], name: "idx_process_runs_workflow_node_idempotency", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["workflow_node_id", "lifecycle_state"], name: "index_process_runs_on_workflow_node_id_and_lifecycle_state"
    t.index ["workflow_node_id"], name: "index_process_runs_on_workflow_node_id"
  end

  create_table "provider_credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "credential_kind", null: false
    t.bigint "installation_id", null: false
    t.datetime "last_rotated_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "provider_handle", null: false
    t.text "secret", null: false
    t.datetime "updated_at", null: false
    t.index ["installation_id", "provider_handle", "credential_kind"], name: "idx_provider_credentials_installation_provider_kind", unique: true
    t.index ["installation_id"], name: "index_provider_credentials_on_installation_id"
  end

  create_table "provider_entitlements", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "entitlement_key", null: false
    t.bigint "installation_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "provider_handle", null: false
    t.integer "quota_limit", null: false
    t.datetime "updated_at", null: false
    t.string "window_kind", null: false
    t.integer "window_seconds"
    t.index ["installation_id", "provider_handle", "entitlement_key"], name: "idx_provider_entitlements_installation_provider_key", unique: true
    t.index ["installation_id"], name: "index_provider_entitlements_on_installation_id"
  end

  create_table "provider_policies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.bigint "installation_id", null: false
    t.string "provider_handle", null: false
    t.jsonb "selection_defaults", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["installation_id", "provider_handle"], name: "index_provider_policies_on_installation_id_and_provider_handle", unique: true
    t.index ["installation_id"], name: "index_provider_policies_on_installation_id"
  end

  create_table "provider_request_controls", force: :cascade do |t|
    t.datetime "cooldown_until"
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.string "last_rate_limit_reason"
    t.datetime "last_rate_limited_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "provider_handle", null: false
    t.datetime "updated_at", null: false
    t.index ["installation_id", "provider_handle"], name: "idx_on_installation_id_provider_handle_c4e00a6aea", unique: true
    t.index ["installation_id"], name: "index_provider_request_controls_on_installation_id"
  end

  create_table "provider_request_leases", force: :cascade do |t|
    t.datetime "acquired_at", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "installation_id", null: false
    t.datetime "last_heartbeat_at", null: false
    t.string "lease_token", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "provider_handle", null: false
    t.string "release_reason"
    t.datetime "released_at"
    t.datetime "updated_at", null: false
    t.bigint "workflow_node_id"
    t.bigint "workflow_run_id"
    t.index ["installation_id", "provider_handle", "expires_at"], name: "idx_provider_request_leases_expiry"
    t.index ["installation_id", "provider_handle", "released_at"], name: "idx_provider_request_leases_scope"
    t.index ["installation_id"], name: "index_provider_request_leases_on_installation_id"
    t.index ["lease_token"], name: "index_provider_request_leases_on_lease_token", unique: true
    t.index ["workflow_node_id"], name: "index_provider_request_leases_on_workflow_node_id"
    t.index ["workflow_run_id"], name: "index_provider_request_leases_on_workflow_run_id"
  end

  create_table "publication_access_events", force: :cascade do |t|
    t.string "access_via", null: false
    t.datetime "accessed_at", null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.bigint "publication_id", null: false
    t.jsonb "request_metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "viewer_user_id"
    t.index ["installation_id"], name: "index_publication_access_events_on_installation_id"
    t.index ["publication_id", "accessed_at"], name: "idx_publication_access_events_publication_accessed_at"
    t.index ["publication_id"], name: "index_publication_access_events_on_publication_id"
    t.index ["viewer_user_id"], name: "index_publication_access_events_on_viewer_user_id"
  end

  create_table "publications", force: :cascade do |t|
    t.string "access_token_digest", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.bigint "owner_user_id", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "published_at"
    t.datetime "revoked_at"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.string "visibility_mode", default: "disabled", null: false
    t.index ["access_token_digest"], name: "index_publications_on_access_token_digest", unique: true
    t.index ["conversation_id"], name: "idx_publications_conversation_unique", unique: true
    t.index ["conversation_id"], name: "index_publications_on_conversation_id"
    t.index ["installation_id"], name: "index_publications_on_installation_id"
    t.index ["owner_user_id"], name: "index_publications_on_owner_user_id"
    t.index ["public_id"], name: "index_publications_on_public_id", unique: true
    t.index ["slug"], name: "index_publications_on_slug", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "identity_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["identity_id"], name: "index_sessions_on_identity_id"
    t.index ["public_id"], name: "index_sessions_on_public_id", unique: true
    t.index ["token_digest"], name: "index_sessions_on_token_digest", unique: true
    t.index ["user_id", "expires_at"], name: "index_sessions_on_user_id_and_expires_at"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "subagent_connections", force: :cascade do |t|
    t.string "blocked_summary"
    t.datetime "close_acknowledged_at"
    t.datetime "close_force_deadline_at"
    t.datetime "close_grace_deadline_at"
    t.string "close_outcome_kind"
    t.jsonb "close_outcome_payload", default: {}, null: false
    t.string "close_reason_kind"
    t.datetime "close_requested_at"
    t.string "close_state", default: "open", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "current_focus_summary"
    t.integer "depth", default: 0, null: false
    t.string "focus_kind", default: "general", null: false
    t.bigint "installation_id", null: false
    t.datetime "last_progress_at"
    t.string "next_step_hint"
    t.string "observed_status", default: "idle", null: false
    t.bigint "origin_turn_id"
    t.bigint "owner_conversation_id", null: false
    t.bigint "parent_subagent_connection_id"
    t.string "profile_key", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "recent_progress_summary"
    t.string "request_summary"
    t.string "scope", default: "turn", null: false
    t.jsonb "supervision_payload", default: {}, null: false
    t.string "supervision_state", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.string "waiting_summary"
    t.index ["conversation_id"], name: "idx_subagent_connections_conversation", unique: true
    t.index ["conversation_id"], name: "index_subagent_connections_on_conversation_id"
    t.index ["installation_id"], name: "index_subagent_connections_on_installation_id"
    t.index ["origin_turn_id"], name: "index_subagent_connections_on_origin_turn_id"
    t.index ["owner_conversation_id", "created_at"], name: "idx_subagent_connections_owner_created"
    t.index ["owner_conversation_id"], name: "index_subagent_connections_on_owner_conversation_id"
    t.index ["parent_subagent_connection_id"], name: "index_subagent_connections_on_parent_subagent_connection_id"
    t.index ["public_id"], name: "index_subagent_connections_on_public_id", unique: true
  end

  create_table "tool_bindings", force: :cascade do |t|
    t.bigint "agent_task_run_id"
    t.string "binding_reason", null: false
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.bigint "installation_id", null: false
    t.boolean "parallel_safe", default: false, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.boolean "round_scoped", default: false, null: false
    t.jsonb "runtime_state", default: {}, null: false
    t.bigint "source_tool_binding_id"
    t.bigint "source_workflow_node_id"
    t.string "tool_call_id"
    t.bigint "tool_definition_id", null: false
    t.bigint "tool_implementation_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workflow_node_id"
    t.index ["agent_task_run_id", "tool_definition_id"], name: "idx_tool_bindings_task_definition", unique: true
    t.index ["agent_task_run_id"], name: "index_tool_bindings_on_agent_task_run_id"
    t.index ["installation_id"], name: "index_tool_bindings_on_installation_id"
    t.index ["public_id"], name: "index_tool_bindings_on_public_id", unique: true
    t.index ["source_tool_binding_id"], name: "index_tool_bindings_on_source_tool_binding_id"
    t.index ["source_workflow_node_id"], name: "index_tool_bindings_on_source_workflow_node_id"
    t.index ["tool_definition_id"], name: "index_tool_bindings_on_tool_definition_id"
    t.index ["tool_implementation_id"], name: "index_tool_bindings_on_tool_implementation_id"
    t.index ["workflow_node_id", "tool_definition_id"], name: "idx_tool_bindings_node_definition", unique: true, where: "((workflow_node_id IS NOT NULL) AND (agent_task_run_id IS NULL))"
    t.index ["workflow_node_id"], name: "index_tool_bindings_on_workflow_node_id"
  end

  create_table "tool_definitions", force: :cascade do |t|
    t.bigint "agent_definition_version_id", null: false
    t.datetime "created_at", null: false
    t.string "governance_mode", null: false
    t.bigint "installation_id", null: false
    t.jsonb "policy_payload", default: {}, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "tool_kind", null: false
    t.string "tool_name", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_definition_version_id", "tool_name"], name: "idx_tool_definitions_definition_tool", unique: true
    t.index ["agent_definition_version_id"], name: "index_tool_definitions_on_agent_definition_version_id"
    t.index ["installation_id"], name: "index_tool_definitions_on_installation_id"
    t.index ["public_id"], name: "index_tool_definitions_on_public_id", unique: true
  end

  create_table "tool_implementations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "default_for_snapshot", default: false, null: false
    t.string "idempotency_policy", null: false
    t.string "implementation_ref", null: false
    t.bigint "implementation_source_id", null: false
    t.jsonb "input_schema", default: {}, null: false
    t.bigint "installation_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.jsonb "result_schema", default: {}, null: false
    t.boolean "streaming_support", default: false, null: false
    t.bigint "tool_definition_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workflow_node_id"
    t.index ["implementation_source_id"], name: "index_tool_implementations_on_implementation_source_id"
    t.index ["installation_id"], name: "index_tool_implementations_on_installation_id"
    t.index ["public_id"], name: "index_tool_implementations_on_public_id", unique: true
    t.index ["tool_definition_id", "implementation_ref"], name: "idx_tool_implementations_definition_ref", unique: true
    t.index ["tool_definition_id"], name: "idx_tool_implementations_one_default", unique: true, where: "default_for_snapshot"
    t.index ["tool_definition_id"], name: "index_tool_implementations_on_tool_definition_id"
    t.index ["workflow_node_id"], name: "index_tool_implementations_on_workflow_node_id"
  end

  create_table "tool_invocations", force: :cascade do |t|
    t.bigint "agent_task_run_id"
    t.integer "attempt_no", default: 1, null: false
    t.datetime "created_at", null: false
    t.bigint "error_document_id"
    t.datetime "finished_at"
    t.string "idempotency_key"
    t.bigint "installation_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "provider_format"
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.bigint "request_document_id"
    t.bigint "response_document_id"
    t.datetime "started_at"
    t.string "status", null: false
    t.boolean "stream_output", default: false, null: false
    t.bigint "tool_binding_id", null: false
    t.bigint "tool_definition_id", null: false
    t.bigint "tool_implementation_id", null: false
    t.bigint "trace_document_id"
    t.datetime "updated_at", null: false
    t.bigint "workflow_node_id"
    t.index ["agent_task_run_id"], name: "index_tool_invocations_on_agent_task_run_id"
    t.index ["error_document_id"], name: "index_tool_invocations_on_error_document_id"
    t.index ["installation_id"], name: "index_tool_invocations_on_installation_id"
    t.index ["public_id"], name: "index_tool_invocations_on_public_id", unique: true
    t.index ["request_document_id"], name: "index_tool_invocations_on_request_document_id"
    t.index ["response_document_id"], name: "index_tool_invocations_on_response_document_id"
    t.index ["tool_binding_id", "attempt_no"], name: "idx_tool_invocations_binding_attempt", unique: true
    t.index ["tool_binding_id", "idempotency_key"], name: "idx_tool_invocations_binding_idempotency", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["tool_binding_id"], name: "index_tool_invocations_on_tool_binding_id"
    t.index ["tool_definition_id"], name: "index_tool_invocations_on_tool_definition_id"
    t.index ["tool_implementation_id"], name: "index_tool_invocations_on_tool_implementation_id"
    t.index ["trace_document_id"], name: "index_tool_invocations_on_trace_document_id"
    t.index ["workflow_node_id"], name: "index_tool_invocations_on_workflow_node_id"
  end

  create_table "turn_diagnostics_snapshots", force: :cascade do |t|
    t.integer "attributed_user_estimated_cost_event_count", default: 0, null: false
    t.integer "attributed_user_estimated_cost_missing_event_count", default: 0, null: false
    t.decimal "attributed_user_estimated_cost_total", precision: 12, scale: 6, default: "0.0", null: false
    t.integer "attributed_user_input_tokens_total", default: 0, null: false
    t.integer "attributed_user_output_tokens_total", default: 0, null: false
    t.integer "attributed_user_usage_event_count", default: 0, null: false
    t.integer "avg_latency_ms", default: 0, null: false
    t.integer "cached_input_tokens_total", default: 0, null: false
    t.integer "command_failure_count", default: 0, null: false
    t.integer "command_run_count", default: 0, null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.integer "estimated_cost_event_count", default: 0, null: false
    t.integer "estimated_cost_missing_event_count", default: 0, null: false
    t.decimal "estimated_cost_total", precision: 12, scale: 6, default: "0.0", null: false
    t.integer "input_tokens_total", default: 0, null: false
    t.integer "input_variant_count", default: 0, null: false
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", null: false
    t.integer "max_latency_ms", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "output_tokens_total", default: 0, null: false
    t.integer "output_variant_count", default: 0, null: false
    t.string "pause_state"
    t.integer "process_failure_count", default: 0, null: false
    t.integer "process_run_count", default: 0, null: false
    t.integer "prompt_cache_available_event_count", default: 0, null: false
    t.integer "prompt_cache_unknown_event_count", default: 0, null: false
    t.integer "prompt_cache_unsupported_event_count", default: 0, null: false
    t.integer "provider_round_count", default: 0, null: false
    t.integer "resume_attempt_count", default: 0, null: false
    t.integer "retry_attempt_count", default: 0, null: false
    t.integer "subagent_connection_count", default: 0, null: false
    t.integer "tool_call_count", default: 0, null: false
    t.integer "tool_failure_count", default: 0, null: false
    t.bigint "turn_id", null: false
    t.datetime "updated_at", null: false
    t.integer "usage_event_count", default: 0, null: false
    t.index ["conversation_id"], name: "index_turn_diagnostics_snapshots_on_conversation_id"
    t.index ["installation_id"], name: "index_turn_diagnostics_snapshots_on_installation_id"
    t.index ["turn_id"], name: "index_turn_diagnostics_snapshots_on_turn_id", unique: true
  end

  create_table "turn_todo_plan_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "delegated_subagent_connection_id"
    t.jsonb "depends_on_item_keys", default: [], null: false
    t.jsonb "details_payload", default: {}, null: false
    t.bigint "installation_id", null: false
    t.string "item_key", null: false
    t.string "kind", null: false
    t.datetime "last_status_changed_at"
    t.integer "position", default: 0, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.bigint "turn_todo_plan_id", null: false
    t.datetime "updated_at", null: false
    t.index ["delegated_subagent_connection_id"], name: "index_turn_todo_plan_items_on_delegated_subagent_connection_id"
    t.index ["installation_id"], name: "index_turn_todo_plan_items_on_installation_id"
    t.index ["public_id"], name: "index_turn_todo_plan_items_on_public_id", unique: true
    t.index ["turn_todo_plan_id", "item_key"], name: "idx_turn_todo_plan_items_plan_key", unique: true
    t.index ["turn_todo_plan_id"], name: "index_turn_todo_plan_items_on_turn_todo_plan_id"
  end

  create_table "turn_todo_plans", force: :cascade do |t|
    t.bigint "agent_task_run_id", null: false
    t.datetime "closed_at"
    t.bigint "conversation_id", null: false
    t.jsonb "counts_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "current_item_key"
    t.string "goal_summary", null: false
    t.bigint "installation_id", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "status", default: "draft", null: false
    t.bigint "turn_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_task_run_id"], name: "idx_turn_todo_plans_single_active_plan", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["agent_task_run_id"], name: "index_turn_todo_plans_on_agent_task_run_id"
    t.index ["conversation_id"], name: "index_turn_todo_plans_on_conversation_id"
    t.index ["installation_id"], name: "index_turn_todo_plans_on_installation_id"
    t.index ["public_id"], name: "index_turn_todo_plans_on_public_id", unique: true
    t.index ["turn_id"], name: "index_turn_todo_plans_on_turn_id"
  end

  create_table "turns", force: :cascade do |t|
    t.string "agent_config_content_fingerprint", null: false
    t.integer "agent_config_version", default: 1, null: false
    t.bigint "agent_definition_version_id", null: false
    t.string "cancellation_reason_kind"
    t.datetime "cancellation_requested_at"
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "execution_contract_id"
    t.bigint "execution_runtime_id"
    t.bigint "execution_runtime_version_id"
    t.string "external_event_key"
    t.jsonb "feature_policy_snapshot", default: {}, null: false
    t.string "idempotency_key"
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", null: false
    t.string "origin_kind", null: false
    t.jsonb "origin_payload", default: {}, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.jsonb "resolved_config_snapshot", default: {}, null: false
    t.jsonb "resolved_model_selection_snapshot", default: {}, null: false
    t.bigint "selected_input_message_id"
    t.bigint "selected_output_message_id"
    t.integer "sequence", null: false
    t.string "source_ref_id"
    t.string "source_ref_type"
    t.datetime "updated_at", null: false
    t.index ["agent_definition_version_id"], name: "index_turns_on_agent_definition_version_id"
    t.index ["conversation_id", "sequence"], name: "index_turns_on_conversation_id_and_sequence", unique: true
    t.index ["conversation_id"], name: "index_turns_on_conversation_id"
    t.index ["execution_contract_id"], name: "index_turns_on_execution_contract_id"
    t.index ["execution_runtime_id"], name: "index_turns_on_execution_runtime_id"
    t.index ["execution_runtime_version_id"], name: "index_turns_on_execution_runtime_version_id"
    t.index ["installation_id"], name: "index_turns_on_installation_id"
    t.index ["public_id"], name: "index_turns_on_public_id", unique: true
    t.index ["selected_input_message_id"], name: "index_turns_on_selected_input_message_id"
    t.index ["selected_output_message_id"], name: "index_turns_on_selected_output_message_id"
    t.check_constraint "cancellation_reason_kind IS NULL AND cancellation_requested_at IS NULL OR cancellation_reason_kind IS NOT NULL AND cancellation_requested_at IS NOT NULL", name: "chk_turns_cancellation_pairing"
    t.check_constraint "cancellation_reason_kind IS NULL OR (cancellation_reason_kind::text = ANY (ARRAY['conversation_deleted'::character varying::text, 'conversation_archived'::character varying::text, 'turn_interrupted'::character varying::text]))", name: "chk_turns_cancellation_reason_kind"
  end

  create_table "usage_events", force: :cascade do |t|
    t.bigint "agent_definition_version_id"
    t.bigint "agent_id"
    t.integer "cached_input_tokens"
    t.bigint "conversation_id"
    t.datetime "created_at", null: false
    t.string "entitlement_window_key"
    t.decimal "estimated_cost", precision: 12, scale: 6
    t.integer "input_tokens"
    t.bigint "installation_id", null: false
    t.integer "latency_ms"
    t.integer "media_units"
    t.string "model_ref", null: false
    t.datetime "occurred_at", null: false
    t.string "operation_kind", null: false
    t.integer "output_tokens"
    t.string "prompt_cache_status", default: "unknown", null: false
    t.string "provider_handle", null: false
    t.boolean "success", null: false
    t.bigint "turn_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "workflow_node_key"
    t.bigint "workspace_id"
    t.index ["agent_definition_version_id"], name: "index_usage_events_on_agent_definition_version_id"
    t.index ["agent_id"], name: "index_usage_events_on_agent_id"
    t.index ["conversation_id"], name: "index_usage_events_on_conversation_id"
    t.index ["installation_id", "occurred_at"], name: "index_usage_events_on_installation_id_and_occurred_at"
    t.index ["installation_id"], name: "index_usage_events_on_installation_id"
    t.index ["provider_handle", "model_ref"], name: "index_usage_events_on_provider_handle_and_model_ref"
    t.index ["turn_id"], name: "index_usage_events_on_turn_id"
    t.index ["user_id"], name: "index_usage_events_on_user_id"
    t.index ["workspace_id"], name: "index_usage_events_on_workspace_id"
  end

  create_table "usage_rollups", force: :cascade do |t|
    t.bigint "agent_definition_version_id"
    t.bigint "agent_id"
    t.string "bucket_key", null: false
    t.string "bucket_kind", null: false
    t.integer "cached_input_tokens_total", default: 0, null: false
    t.bigint "conversation_id"
    t.datetime "created_at", null: false
    t.string "dimension_digest", null: false
    t.decimal "estimated_cost_total", precision: 12, scale: 6, default: "0.0", null: false
    t.integer "event_count", default: 0, null: false
    t.integer "failure_count", default: 0, null: false
    t.integer "input_tokens_total", default: 0, null: false
    t.bigint "installation_id", null: false
    t.integer "media_units_total", default: 0, null: false
    t.string "model_ref", null: false
    t.string "operation_kind", null: false
    t.integer "output_tokens_total", default: 0, null: false
    t.integer "prompt_cache_available_event_count", default: 0, null: false
    t.integer "prompt_cache_unknown_event_count", default: 0, null: false
    t.integer "prompt_cache_unsupported_event_count", default: 0, null: false
    t.string "provider_handle", null: false
    t.integer "success_count", default: 0, null: false
    t.integer "total_latency_ms", default: 0, null: false
    t.bigint "turn_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "workflow_node_key"
    t.bigint "workspace_id"
    t.index ["agent_definition_version_id"], name: "index_usage_rollups_on_agent_definition_version_id"
    t.index ["agent_id"], name: "index_usage_rollups_on_agent_id"
    t.index ["installation_id", "bucket_kind", "bucket_key", "dimension_digest"], name: "idx_usage_rollups_installation_bucket_dimension", unique: true
    t.index ["installation_id"], name: "index_usage_rollups_on_installation_id"
    t.index ["user_id"], name: "index_usage_rollups_on_user_id"
    t.index ["workspace_id"], name: "index_usage_rollups_on_workspace_id"
  end

  create_table "user_agent_bindings", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.jsonb "preferences", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["agent_id"], name: "index_user_agent_bindings_on_agent_id"
    t.index ["installation_id", "user_id"], name: "index_user_agent_bindings_on_installation_id_and_user_id"
    t.index ["installation_id"], name: "index_user_agent_bindings_on_installation_id"
    t.index ["user_id", "agent_id"], name: "index_user_agent_bindings_on_user_id_and_agent_id", unique: true
    t.index ["user_id"], name: "index_user_agent_bindings_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.bigint "identity_id", null: false
    t.bigint "installation_id", null: false
    t.jsonb "preferences", default: {}, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.index ["identity_id"], name: "index_users_on_identity_id", unique: true
    t.index ["installation_id", "role"], name: "index_users_on_installation_id_and_role"
    t.index ["installation_id"], name: "index_users_on_installation_id"
    t.index ["public_id"], name: "index_users_on_public_id", unique: true
  end

  create_table "workflow_artifacts", force: :cascade do |t|
    t.string "artifact_key", null: false
    t.string "artifact_kind", null: false
    t.bigint "conversation_id"
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.bigint "json_document_id"
    t.string "presentation_policy"
    t.string "storage_mode", null: false
    t.bigint "turn_id"
    t.datetime "updated_at", null: false
    t.bigint "workflow_node_id", null: false
    t.string "workflow_node_key"
    t.integer "workflow_node_ordinal"
    t.bigint "workflow_run_id", null: false
    t.bigint "workspace_id"
    t.index ["conversation_id", "workflow_node_ordinal", "artifact_kind"], name: "index_workflow_artifacts_on_conversation_node_ordinal_kind"
    t.index ["conversation_id"], name: "index_workflow_artifacts_on_conversation_id"
    t.index ["installation_id"], name: "index_workflow_artifacts_on_installation_id"
    t.index ["json_document_id"], name: "index_workflow_artifacts_on_json_document_id"
    t.index ["turn_id"], name: "index_workflow_artifacts_on_turn_id"
    t.index ["workflow_node_id", "artifact_kind"], name: "index_workflow_artifacts_on_workflow_node_id_and_artifact_kind"
    t.index ["workflow_node_id"], name: "index_workflow_artifacts_on_workflow_node_id"
    t.index ["workflow_run_id", "artifact_key"], name: "index_workflow_artifacts_on_workflow_run_id_and_artifact_key"
    t.index ["workflow_run_id"], name: "index_workflow_artifacts_on_workflow_run_id"
    t.index ["workspace_id"], name: "index_workflow_artifacts_on_workspace_id"
    t.check_constraint "presentation_policy::text = ANY (ARRAY['internal_only'::character varying, 'ops_trackable'::character varying, 'user_projectable'::character varying]::text[])", name: "chk_workflow_artifacts_presentation_policy"
  end

  create_table "workflow_edges", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "from_node_id", null: false
    t.bigint "installation_id", null: false
    t.integer "ordinal", null: false
    t.string "requirement", default: "required", null: false
    t.bigint "to_node_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workflow_run_id", null: false
    t.index ["from_node_id"], name: "index_workflow_edges_on_from_node_id"
    t.index ["installation_id"], name: "index_workflow_edges_on_installation_id"
    t.index ["to_node_id"], name: "index_workflow_edges_on_to_node_id"
    t.index ["workflow_run_id", "from_node_id", "ordinal"], name: "idx_on_workflow_run_id_from_node_id_ordinal_2bc1936b9e", unique: true
    t.index ["workflow_run_id", "from_node_id", "to_node_id"], name: "idx_on_workflow_run_id_from_node_id_to_node_id_54f159bded", unique: true
    t.index ["workflow_run_id"], name: "index_workflow_edges_on_workflow_run_id"
    t.check_constraint "requirement::text = ANY (ARRAY['required'::character varying, 'optional'::character varying]::text[])", name: "chk_workflow_edges_requirement"
  end

  create_table "workflow_node_events", force: :cascade do |t|
    t.bigint "conversation_id"
    t.datetime "created_at", null: false
    t.string "event_kind", null: false
    t.bigint "installation_id", null: false
    t.integer "ordinal", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "presentation_policy"
    t.bigint "turn_id"
    t.datetime "updated_at", null: false
    t.bigint "workflow_node_id", null: false
    t.string "workflow_node_key"
    t.integer "workflow_node_ordinal"
    t.bigint "workflow_run_id", null: false
    t.bigint "workspace_id"
    t.index ["conversation_id", "workflow_node_ordinal", "ordinal"], name: "index_workflow_node_events_on_conversation_node_ordinal"
    t.index ["conversation_id"], name: "index_workflow_node_events_on_conversation_id"
    t.index ["installation_id"], name: "index_workflow_node_events_on_installation_id"
    t.index ["turn_id"], name: "index_workflow_node_events_on_turn_id"
    t.index ["workflow_node_id", "ordinal"], name: "index_workflow_node_events_on_workflow_node_id_and_ordinal", unique: true
    t.index ["workflow_node_id"], name: "index_workflow_node_events_on_workflow_node_id"
    t.index ["workflow_run_id", "event_kind"], name: "index_workflow_node_events_on_workflow_run_id_and_event_kind"
    t.index ["workflow_run_id"], name: "index_workflow_node_events_on_workflow_run_id"
    t.index ["workspace_id"], name: "index_workflow_node_events_on_workspace_id"
    t.check_constraint "presentation_policy::text = ANY (ARRAY['internal_only'::character varying, 'ops_trackable'::character varying, 'user_projectable'::character varying]::text[])", name: "chk_workflow_node_events_presentation_policy"
  end

  create_table "workflow_nodes", force: :cascade do |t|
    t.integer "blocked_retry_attempt_no"
    t.string "blocked_retry_failure_kind"
    t.bigint "conversation_id"
    t.datetime "created_at", null: false
    t.string "decision_source", null: false
    t.datetime "finished_at"
    t.bigint "installation_id", null: false
    t.string "intent_batch_id"
    t.string "intent_conflict_scope"
    t.string "intent_id"
    t.string "intent_idempotency_key"
    t.string "intent_kind"
    t.string "intent_requirement"
    t.string "lifecycle_state", default: "pending", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "node_key", null: false
    t.string "node_type", null: false
    t.bigint "opened_human_interaction_request_id"
    t.integer "ordinal", null: false
    t.string "presentation_policy"
    t.text "prior_tool_node_keys", default: [], null: false, array: true
    t.integer "provider_round_index"
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.bigint "spawned_subagent_connection_id"
    t.integer "stage_index"
    t.integer "stage_position"
    t.datetime "started_at"
    t.bigint "tool_call_document_id"
    t.boolean "transcript_side_effect_committed", default: false, null: false
    t.bigint "turn_id"
    t.datetime "updated_at", null: false
    t.bigint "workflow_run_id", null: false
    t.bigint "workspace_id"
    t.bigint "yielding_workflow_node_id"
    t.index ["conversation_id"], name: "index_workflow_nodes_on_conversation_id"
    t.index ["installation_id"], name: "index_workflow_nodes_on_installation_id"
    t.index ["opened_human_interaction_request_id"], name: "index_workflow_nodes_on_opened_human_interaction_request_id"
    t.index ["public_id"], name: "index_workflow_nodes_on_public_id", unique: true
    t.index ["spawned_subagent_connection_id"], name: "index_workflow_nodes_on_spawned_subagent_connection_id"
    t.index ["tool_call_document_id"], name: "index_workflow_nodes_on_tool_call_document_id"
    t.index ["turn_id"], name: "index_workflow_nodes_on_turn_id"
    t.index ["workflow_run_id", "lifecycle_state", "ordinal"], name: "index_workflow_nodes_on_run_state_order"
    t.index ["workflow_run_id", "node_key"], name: "index_workflow_nodes_on_workflow_run_id_and_node_key", unique: true
    t.index ["workflow_run_id", "ordinal"], name: "index_workflow_nodes_on_workflow_run_id_and_ordinal", unique: true
    t.index ["workflow_run_id", "stage_index", "stage_position"], name: "index_workflow_nodes_on_run_stage_order"
    t.index ["workflow_run_id"], name: "index_workflow_nodes_on_workflow_run_id"
    t.index ["workspace_id"], name: "index_workflow_nodes_on_workspace_id"
    t.index ["yielding_workflow_node_id"], name: "index_workflow_nodes_on_yielding_workflow_node_id"
    t.check_constraint "lifecycle_state::text = ANY (ARRAY['pending'::character varying, 'queued'::character varying, 'running'::character varying, 'waiting'::character varying, 'completed'::character varying, 'failed'::character varying, 'canceled'::character varying]::text[])", name: "chk_workflow_nodes_lifecycle_state"
    t.check_constraint "presentation_policy::text = ANY (ARRAY['internal_only'::character varying, 'ops_trackable'::character varying, 'user_projectable'::character varying]::text[])", name: "chk_workflow_nodes_presentation_policy"
  end

  create_table "workflow_runs", force: :cascade do |t|
    t.string "blocking_resource_id"
    t.string "blocking_resource_type"
    t.string "cancellation_reason_kind"
    t.datetime "cancellation_requested_at"
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", default: "active", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "recovery_agent_task_run_public_id"
    t.string "recovery_drift_reason"
    t.string "recovery_reason"
    t.string "recovery_state"
    t.string "resume_batch_id"
    t.string "resume_policy"
    t.string "resume_successor_node_key"
    t.string "resume_successor_node_type"
    t.string "resume_yielding_node_key"
    t.bigint "turn_id", null: false
    t.datetime "updated_at", null: false
    t.integer "wait_attempt_no"
    t.string "wait_failure_kind"
    t.text "wait_last_error_summary"
    t.integer "wait_max_auto_retries"
    t.datetime "wait_next_retry_at"
    t.string "wait_policy_mode"
    t.string "wait_reason_kind"
    t.jsonb "wait_reason_payload", default: {}, null: false
    t.string "wait_resume_mode"
    t.string "wait_retry_scope"
    t.string "wait_retry_strategy"
    t.bigint "wait_snapshot_document_id"
    t.string "wait_state", default: "ready", null: false
    t.datetime "waiting_since_at"
    t.index ["conversation_id"], name: "index_workflow_runs_on_conversation_id"
    t.index ["conversation_id"], name: "index_workflow_runs_on_conversation_id_active", unique: true, where: "((lifecycle_state)::text = 'active'::text)"
    t.index ["installation_id"], name: "index_workflow_runs_on_installation_id"
    t.index ["public_id"], name: "index_workflow_runs_on_public_id", unique: true
    t.index ["turn_id"], name: "index_workflow_runs_on_turn_id", unique: true
    t.index ["wait_snapshot_document_id"], name: "index_workflow_runs_on_wait_snapshot_document_id"
    t.check_constraint "cancellation_reason_kind IS NULL AND cancellation_requested_at IS NULL OR cancellation_reason_kind IS NOT NULL AND cancellation_requested_at IS NOT NULL", name: "chk_workflow_runs_cancellation_pairing"
    t.check_constraint "cancellation_reason_kind IS NULL OR (cancellation_reason_kind::text = ANY (ARRAY['conversation_deleted'::character varying::text, 'conversation_archived'::character varying::text, 'turn_interrupted'::character varying::text]))", name: "chk_workflow_runs_cancellation_reason_kind"
    t.check_constraint "resume_policy IS NULL OR resume_policy::text = 're_enter_agent'::text", name: "chk_workflow_runs_resume_policy"
  end

  create_table "workspaces", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "default_execution_runtime_id"
    t.bigint "installation_id", null: false
    t.boolean "is_default", default: false, null: false
    t.string "name", null: false
    t.string "privacy", default: "private", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_agent_binding_id", null: false
    t.bigint "user_id", null: false
    t.index ["default_execution_runtime_id"], name: "index_workspaces_on_default_execution_runtime_id"
    t.index ["installation_id", "user_id"], name: "index_workspaces_on_installation_id_and_user_id"
    t.index ["installation_id"], name: "index_workspaces_on_installation_id"
    t.index ["public_id"], name: "index_workspaces_on_public_id", unique: true
    t.index ["user_agent_binding_id"], name: "index_workspaces_on_user_agent_binding_id"
    t.index ["user_agent_binding_id"], name: "index_workspaces_on_user_agent_binding_id_default", unique: true, where: "is_default"
    t.index ["user_id"], name: "index_workspaces_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_config_states", "agent_definition_versions", column: "base_agent_definition_version_id"
  add_foreign_key "agent_config_states", "agents"
  add_foreign_key "agent_config_states", "installations"
  add_foreign_key "agent_config_states", "json_documents", column: "effective_document_id"
  add_foreign_key "agent_config_states", "json_documents", column: "override_document_id"
  add_foreign_key "agent_connections", "agent_definition_versions"
  add_foreign_key "agent_connections", "agents"
  add_foreign_key "agent_connections", "installations"
  add_foreign_key "agent_control_mailbox_items", "agent_connections", column: "leased_to_agent_connection_id"
  add_foreign_key "agent_control_mailbox_items", "agent_definition_versions", column: "target_agent_definition_version_id"
  add_foreign_key "agent_control_mailbox_items", "agent_task_runs"
  add_foreign_key "agent_control_mailbox_items", "agents", column: "target_agent_id"
  add_foreign_key "agent_control_mailbox_items", "execution_contracts"
  add_foreign_key "agent_control_mailbox_items", "execution_runtime_connections", column: "leased_to_execution_runtime_connection_id"
  add_foreign_key "agent_control_mailbox_items", "execution_runtimes", column: "target_execution_runtime_id"
  add_foreign_key "agent_control_mailbox_items", "installations"
  add_foreign_key "agent_control_mailbox_items", "json_documents", column: "payload_document_id"
  add_foreign_key "agent_control_mailbox_items", "workflow_nodes"
  add_foreign_key "agent_control_report_receipts", "agent_connections"
  add_foreign_key "agent_control_report_receipts", "agent_control_mailbox_items", column: "mailbox_item_id"
  add_foreign_key "agent_control_report_receipts", "agent_task_runs"
  add_foreign_key "agent_control_report_receipts", "execution_runtime_connections"
  add_foreign_key "agent_control_report_receipts", "installations"
  add_foreign_key "agent_control_report_receipts", "json_documents", column: "report_document_id"
  add_foreign_key "agent_definition_versions", "agents"
  add_foreign_key "agent_definition_versions", "installations"
  add_foreign_key "agent_definition_versions", "json_documents", column: "canonical_config_schema_document_id"
  add_foreign_key "agent_definition_versions", "json_documents", column: "conversation_override_schema_document_id"
  add_foreign_key "agent_definition_versions", "json_documents", column: "default_canonical_config_document_id"
  add_foreign_key "agent_definition_versions", "json_documents", column: "profile_policy_document_id"
  add_foreign_key "agent_definition_versions", "json_documents", column: "protocol_methods_document_id"
  add_foreign_key "agent_definition_versions", "json_documents", column: "reflected_surface_document_id"
  add_foreign_key "agent_definition_versions", "json_documents", column: "tool_contract_document_id"
  add_foreign_key "agent_task_progress_entries", "agent_task_runs", on_delete: :cascade
  add_foreign_key "agent_task_progress_entries", "installations"
  add_foreign_key "agent_task_progress_entries", "subagent_connections"
  add_foreign_key "agent_task_runs", "agent_connections", column: "holder_agent_connection_id"
  add_foreign_key "agent_task_runs", "agents"
  add_foreign_key "agent_task_runs", "conversations"
  add_foreign_key "agent_task_runs", "installations"
  add_foreign_key "agent_task_runs", "subagent_connections"
  add_foreign_key "agent_task_runs", "turns"
  add_foreign_key "agent_task_runs", "turns", column: "origin_turn_id"
  add_foreign_key "agent_task_runs", "workflow_nodes"
  add_foreign_key "agent_task_runs", "workflow_runs"
  add_foreign_key "agents", "agent_definition_versions", column: "published_agent_definition_version_id"
  add_foreign_key "agents", "execution_runtimes", column: "default_execution_runtime_id"
  add_foreign_key "agents", "installations"
  add_foreign_key "agents", "users", column: "owner_user_id"
  add_foreign_key "audit_logs", "installations"
  add_foreign_key "canonical_variables", "canonical_variables", column: "superseded_by_id"
  add_foreign_key "canonical_variables", "conversations", column: "source_conversation_id"
  add_foreign_key "canonical_variables", "installations"
  add_foreign_key "canonical_variables", "turns", column: "source_turn_id"
  add_foreign_key "canonical_variables", "workflow_runs", column: "source_workflow_run_id"
  add_foreign_key "canonical_variables", "workspaces"
  add_foreign_key "command_runs", "agent_task_runs"
  add_foreign_key "command_runs", "installations"
  add_foreign_key "command_runs", "tool_invocations"
  add_foreign_key "command_runs", "workflow_nodes"
  add_foreign_key "conversation_bundle_import_requests", "conversations", column: "imported_conversation_id"
  add_foreign_key "conversation_bundle_import_requests", "installations"
  add_foreign_key "conversation_bundle_import_requests", "users"
  add_foreign_key "conversation_bundle_import_requests", "workspaces"
  add_foreign_key "conversation_capability_grants", "conversations", column: "target_conversation_id"
  add_foreign_key "conversation_capability_grants", "installations"
  add_foreign_key "conversation_capability_policies", "conversations", column: "target_conversation_id"
  add_foreign_key "conversation_capability_policies", "installations"
  add_foreign_key "conversation_close_operations", "conversations"
  add_foreign_key "conversation_close_operations", "installations"
  add_foreign_key "conversation_closures", "conversations", column: "ancestor_conversation_id"
  add_foreign_key "conversation_closures", "conversations", column: "descendant_conversation_id"
  add_foreign_key "conversation_closures", "installations"
  add_foreign_key "conversation_control_requests", "conversation_supervision_sessions"
  add_foreign_key "conversation_control_requests", "conversations", column: "target_conversation_id"
  add_foreign_key "conversation_control_requests", "installations"
  add_foreign_key "conversation_debug_export_requests", "conversations"
  add_foreign_key "conversation_debug_export_requests", "installations"
  add_foreign_key "conversation_debug_export_requests", "users"
  add_foreign_key "conversation_debug_export_requests", "workspaces"
  add_foreign_key "conversation_diagnostics_snapshots", "conversations"
  add_foreign_key "conversation_diagnostics_snapshots", "installations"
  add_foreign_key "conversation_diagnostics_snapshots", "turns", column: "most_expensive_turn_id"
  add_foreign_key "conversation_diagnostics_snapshots", "turns", column: "most_rounds_turn_id"
  add_foreign_key "conversation_events", "conversations"
  add_foreign_key "conversation_events", "installations"
  add_foreign_key "conversation_events", "turns"
  add_foreign_key "conversation_export_requests", "conversations"
  add_foreign_key "conversation_export_requests", "installations"
  add_foreign_key "conversation_export_requests", "users"
  add_foreign_key "conversation_export_requests", "workspaces"
  add_foreign_key "conversation_imports", "conversation_summary_segments", column: "summary_segment_id"
  add_foreign_key "conversation_imports", "conversations"
  add_foreign_key "conversation_imports", "conversations", column: "source_conversation_id"
  add_foreign_key "conversation_imports", "installations"
  add_foreign_key "conversation_imports", "messages", column: "source_message_id"
  add_foreign_key "conversation_message_visibilities", "conversations"
  add_foreign_key "conversation_message_visibilities", "installations"
  add_foreign_key "conversation_message_visibilities", "messages"
  add_foreign_key "conversation_summary_segments", "conversation_summary_segments", column: "superseded_by_id"
  add_foreign_key "conversation_summary_segments", "conversations"
  add_foreign_key "conversation_summary_segments", "installations"
  add_foreign_key "conversation_summary_segments", "messages", column: "end_message_id"
  add_foreign_key "conversation_summary_segments", "messages", column: "start_message_id"
  add_foreign_key "conversation_supervision_feed_entries", "conversations", column: "target_conversation_id"
  add_foreign_key "conversation_supervision_feed_entries", "installations"
  add_foreign_key "conversation_supervision_feed_entries", "turns", column: "target_turn_id"
  add_foreign_key "conversation_supervision_messages", "conversation_supervision_sessions"
  add_foreign_key "conversation_supervision_messages", "conversation_supervision_snapshots"
  add_foreign_key "conversation_supervision_messages", "conversations", column: "target_conversation_id"
  add_foreign_key "conversation_supervision_messages", "installations"
  add_foreign_key "conversation_supervision_sessions", "conversations", column: "target_conversation_id"
  add_foreign_key "conversation_supervision_sessions", "installations"
  add_foreign_key "conversation_supervision_snapshots", "conversation_supervision_sessions"
  add_foreign_key "conversation_supervision_snapshots", "conversations", column: "target_conversation_id"
  add_foreign_key "conversation_supervision_snapshots", "installations"
  add_foreign_key "conversation_supervision_states", "conversations", column: "target_conversation_id"
  add_foreign_key "conversation_supervision_states", "installations"
  add_foreign_key "conversations", "agents"
  add_foreign_key "conversations", "conversations", column: "parent_conversation_id"
  add_foreign_key "conversations", "installations"
  add_foreign_key "conversations", "workspaces"
  add_foreign_key "execution_capability_snapshots", "agent_definition_versions"
  add_foreign_key "execution_capability_snapshots", "conversations", column: "owner_conversation_id"
  add_foreign_key "execution_capability_snapshots", "installations"
  add_foreign_key "execution_capability_snapshots", "json_documents", column: "tool_surface_document_id"
  add_foreign_key "execution_capability_snapshots", "subagent_connections"
  add_foreign_key "execution_capability_snapshots", "subagent_connections", column: "parent_subagent_connection_id"
  add_foreign_key "execution_context_snapshots", "installations"
  add_foreign_key "execution_contracts", "agent_definition_versions"
  add_foreign_key "execution_contracts", "execution_capability_snapshots"
  add_foreign_key "execution_contracts", "execution_context_snapshots"
  add_foreign_key "execution_contracts", "execution_runtime_versions"
  add_foreign_key "execution_contracts", "execution_runtimes"
  add_foreign_key "execution_contracts", "installations"
  add_foreign_key "execution_contracts", "messages", column: "selected_input_message_id"
  add_foreign_key "execution_contracts", "messages", column: "selected_output_message_id"
  add_foreign_key "execution_contracts", "turns"
  add_foreign_key "execution_leases", "installations"
  add_foreign_key "execution_leases", "workflow_nodes"
  add_foreign_key "execution_leases", "workflow_runs"
  add_foreign_key "execution_profile_facts", "installations"
  add_foreign_key "execution_profile_facts", "users"
  add_foreign_key "execution_profile_facts", "workspaces"
  add_foreign_key "execution_runtime_connections", "execution_runtime_versions"
  add_foreign_key "execution_runtime_connections", "execution_runtimes"
  add_foreign_key "execution_runtime_connections", "installations"
  add_foreign_key "execution_runtime_versions", "execution_runtimes"
  add_foreign_key "execution_runtime_versions", "installations"
  add_foreign_key "execution_runtime_versions", "json_documents", column: "capability_payload_document_id"
  add_foreign_key "execution_runtime_versions", "json_documents", column: "reflected_host_metadata_document_id"
  add_foreign_key "execution_runtime_versions", "json_documents", column: "tool_catalog_document_id"
  add_foreign_key "execution_runtimes", "execution_runtime_versions", column: "published_execution_runtime_version_id"
  add_foreign_key "execution_runtimes", "installations"
  add_foreign_key "execution_runtimes", "users", column: "owner_user_id"
  add_foreign_key "human_interaction_requests", "conversations"
  add_foreign_key "human_interaction_requests", "installations"
  add_foreign_key "human_interaction_requests", "turns"
  add_foreign_key "human_interaction_requests", "workflow_nodes"
  add_foreign_key "human_interaction_requests", "workflow_runs"
  add_foreign_key "implementation_sources", "installations"
  add_foreign_key "invitations", "installations"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "json_documents", "installations"
  add_foreign_key "lineage_store_entries", "lineage_store_snapshots"
  add_foreign_key "lineage_store_entries", "lineage_store_values"
  add_foreign_key "lineage_store_references", "lineage_store_snapshots"
  add_foreign_key "lineage_store_snapshots", "lineage_store_snapshots", column: "base_snapshot_id"
  add_foreign_key "lineage_store_snapshots", "lineage_stores"
  add_foreign_key "lineage_stores", "conversations", column: "root_conversation_id"
  add_foreign_key "lineage_stores", "installations"
  add_foreign_key "lineage_stores", "workspaces"
  add_foreign_key "message_attachments", "conversations"
  add_foreign_key "message_attachments", "installations"
  add_foreign_key "message_attachments", "message_attachments", column: "origin_attachment_id"
  add_foreign_key "message_attachments", "messages"
  add_foreign_key "message_attachments", "messages", column: "origin_message_id"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "installations"
  add_foreign_key "messages", "messages", column: "source_input_message_id"
  add_foreign_key "messages", "turns"
  add_foreign_key "pairing_sessions", "agents"
  add_foreign_key "pairing_sessions", "installations"
  add_foreign_key "process_runs", "conversations"
  add_foreign_key "process_runs", "execution_runtimes"
  add_foreign_key "process_runs", "installations"
  add_foreign_key "process_runs", "messages", column: "origin_message_id"
  add_foreign_key "process_runs", "turns"
  add_foreign_key "process_runs", "workflow_nodes"
  add_foreign_key "provider_credentials", "installations"
  add_foreign_key "provider_entitlements", "installations"
  add_foreign_key "provider_policies", "installations"
  add_foreign_key "provider_request_controls", "installations"
  add_foreign_key "provider_request_leases", "installations"
  add_foreign_key "provider_request_leases", "workflow_nodes"
  add_foreign_key "provider_request_leases", "workflow_runs"
  add_foreign_key "publication_access_events", "installations"
  add_foreign_key "publication_access_events", "publications"
  add_foreign_key "publication_access_events", "users", column: "viewer_user_id"
  add_foreign_key "publications", "conversations"
  add_foreign_key "publications", "installations"
  add_foreign_key "publications", "users", column: "owner_user_id"
  add_foreign_key "sessions", "identities"
  add_foreign_key "sessions", "users"
  add_foreign_key "subagent_connections", "conversations"
  add_foreign_key "subagent_connections", "conversations", column: "owner_conversation_id"
  add_foreign_key "subagent_connections", "installations"
  add_foreign_key "subagent_connections", "subagent_connections", column: "parent_subagent_connection_id"
  add_foreign_key "subagent_connections", "turns", column: "origin_turn_id"
  add_foreign_key "tool_bindings", "agent_task_runs"
  add_foreign_key "tool_bindings", "installations"
  add_foreign_key "tool_bindings", "tool_bindings", column: "source_tool_binding_id"
  add_foreign_key "tool_bindings", "tool_definitions"
  add_foreign_key "tool_bindings", "tool_implementations"
  add_foreign_key "tool_bindings", "workflow_nodes"
  add_foreign_key "tool_bindings", "workflow_nodes", column: "source_workflow_node_id"
  add_foreign_key "tool_definitions", "agent_definition_versions"
  add_foreign_key "tool_definitions", "installations"
  add_foreign_key "tool_implementations", "implementation_sources"
  add_foreign_key "tool_implementations", "installations"
  add_foreign_key "tool_implementations", "tool_definitions"
  add_foreign_key "tool_implementations", "workflow_nodes"
  add_foreign_key "tool_invocations", "agent_task_runs"
  add_foreign_key "tool_invocations", "installations"
  add_foreign_key "tool_invocations", "json_documents", column: "error_document_id"
  add_foreign_key "tool_invocations", "json_documents", column: "request_document_id"
  add_foreign_key "tool_invocations", "json_documents", column: "response_document_id"
  add_foreign_key "tool_invocations", "json_documents", column: "trace_document_id"
  add_foreign_key "tool_invocations", "tool_bindings"
  add_foreign_key "tool_invocations", "tool_definitions"
  add_foreign_key "tool_invocations", "tool_implementations"
  add_foreign_key "tool_invocations", "workflow_nodes"
  add_foreign_key "turn_diagnostics_snapshots", "conversations"
  add_foreign_key "turn_diagnostics_snapshots", "installations"
  add_foreign_key "turn_diagnostics_snapshots", "turns"
  add_foreign_key "turn_todo_plan_items", "installations"
  add_foreign_key "turn_todo_plan_items", "subagent_connections", column: "delegated_subagent_connection_id"
  add_foreign_key "turn_todo_plan_items", "turn_todo_plans", on_delete: :cascade
  add_foreign_key "turn_todo_plans", "agent_task_runs", on_delete: :cascade
  add_foreign_key "turn_todo_plans", "conversations"
  add_foreign_key "turn_todo_plans", "installations"
  add_foreign_key "turn_todo_plans", "turns"
  add_foreign_key "turns", "agent_definition_versions"
  add_foreign_key "turns", "conversations"
  add_foreign_key "turns", "execution_contracts"
  add_foreign_key "turns", "execution_runtime_versions"
  add_foreign_key "turns", "execution_runtimes"
  add_foreign_key "turns", "installations"
  add_foreign_key "turns", "messages", column: "selected_input_message_id"
  add_foreign_key "turns", "messages", column: "selected_output_message_id"
  add_foreign_key "usage_events", "agent_definition_versions"
  add_foreign_key "usage_events", "agents"
  add_foreign_key "usage_events", "installations"
  add_foreign_key "usage_events", "users"
  add_foreign_key "usage_events", "workspaces"
  add_foreign_key "usage_rollups", "agent_definition_versions"
  add_foreign_key "usage_rollups", "agents"
  add_foreign_key "usage_rollups", "installations"
  add_foreign_key "usage_rollups", "users"
  add_foreign_key "usage_rollups", "workspaces"
  add_foreign_key "user_agent_bindings", "agents"
  add_foreign_key "user_agent_bindings", "installations"
  add_foreign_key "user_agent_bindings", "users"
  add_foreign_key "users", "identities"
  add_foreign_key "users", "installations"
  add_foreign_key "workflow_artifacts", "conversations"
  add_foreign_key "workflow_artifacts", "installations"
  add_foreign_key "workflow_artifacts", "json_documents"
  add_foreign_key "workflow_artifacts", "turns"
  add_foreign_key "workflow_artifacts", "workflow_nodes"
  add_foreign_key "workflow_artifacts", "workflow_runs"
  add_foreign_key "workflow_artifacts", "workspaces"
  add_foreign_key "workflow_edges", "installations"
  add_foreign_key "workflow_edges", "workflow_nodes", column: "from_node_id"
  add_foreign_key "workflow_edges", "workflow_nodes", column: "to_node_id"
  add_foreign_key "workflow_edges", "workflow_runs"
  add_foreign_key "workflow_node_events", "conversations"
  add_foreign_key "workflow_node_events", "installations"
  add_foreign_key "workflow_node_events", "turns"
  add_foreign_key "workflow_node_events", "workflow_nodes"
  add_foreign_key "workflow_node_events", "workflow_runs"
  add_foreign_key "workflow_node_events", "workspaces"
  add_foreign_key "workflow_nodes", "conversations"
  add_foreign_key "workflow_nodes", "human_interaction_requests", column: "opened_human_interaction_request_id"
  add_foreign_key "workflow_nodes", "installations"
  add_foreign_key "workflow_nodes", "json_documents", column: "tool_call_document_id"
  add_foreign_key "workflow_nodes", "subagent_connections", column: "spawned_subagent_connection_id"
  add_foreign_key "workflow_nodes", "turns"
  add_foreign_key "workflow_nodes", "workflow_nodes", column: "yielding_workflow_node_id"
  add_foreign_key "workflow_nodes", "workflow_runs"
  add_foreign_key "workflow_nodes", "workspaces"
  add_foreign_key "workflow_runs", "conversations"
  add_foreign_key "workflow_runs", "installations"
  add_foreign_key "workflow_runs", "json_documents", column: "wait_snapshot_document_id"
  add_foreign_key "workflow_runs", "turns"
  add_foreign_key "workspaces", "execution_runtimes", column: "default_execution_runtime_id"
  add_foreign_key "workspaces", "installations"
  add_foreign_key "workspaces", "user_agent_bindings"
  add_foreign_key "workspaces", "users"
end
