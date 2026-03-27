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

ActiveRecord::Schema[8.2].define(version: 2026_03_27_110000) do
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

  create_table "agent_control_mailbox_items", force: :cascade do |t|
    t.datetime "acked_at"
    t.bigint "agent_task_run_id"
    t.integer "attempt_no", default: 1, null: false
    t.datetime "available_at", null: false
    t.string "causation_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "delivery_no", default: 0, null: false
    t.datetime "dispatch_deadline_at", null: false
    t.datetime "execution_hard_deadline_at"
    t.datetime "failed_at"
    t.bigint "installation_id", null: false
    t.string "item_type", null: false
    t.datetime "lease_expires_at"
    t.integer "lease_timeout_seconds", default: 30, null: false
    t.datetime "leased_at"
    t.bigint "leased_to_agent_deployment_id"
    t.string "logical_work_id", null: false
    t.string "message_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.integer "priority", default: 1, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "status", default: "queued", null: false
    t.bigint "target_agent_deployment_id"
    t.bigint "target_agent_installation_id", null: false
    t.string "target_kind", null: false
    t.string "target_ref", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_task_run_id"], name: "index_agent_control_mailbox_items_on_agent_task_run_id"
    t.index ["installation_id", "message_id"], name: "idx_agent_control_mailbox_items_message", unique: true
    t.index ["installation_id"], name: "index_agent_control_mailbox_items_on_installation_id"
    t.index ["leased_to_agent_deployment_id"], name: "idx_on_leased_to_agent_deployment_id_0933e88604"
    t.index ["public_id"], name: "index_agent_control_mailbox_items_on_public_id", unique: true
    t.index ["target_agent_deployment_id", "status", "priority", "available_at"], name: "idx_agent_control_mailbox_deployment_delivery"
    t.index ["target_agent_deployment_id"], name: "idx_on_target_agent_deployment_id_9a3acfd81e"
    t.index ["target_agent_installation_id", "status", "priority", "available_at"], name: "idx_agent_control_mailbox_installation_delivery"
    t.index ["target_agent_installation_id"], name: "idx_on_target_agent_installation_id_b0ef2265cc"
  end

  create_table "agent_control_report_receipts", force: :cascade do |t|
    t.bigint "agent_deployment_id", null: false
    t.bigint "agent_task_run_id"
    t.integer "attempt_no"
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.string "logical_work_id"
    t.bigint "mailbox_item_id"
    t.string "message_id", null: false
    t.string "method_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "result_code", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_deployment_id"], name: "index_agent_control_report_receipts_on_agent_deployment_id"
    t.index ["agent_task_run_id"], name: "index_agent_control_report_receipts_on_agent_task_run_id"
    t.index ["installation_id", "message_id"], name: "idx_agent_control_report_receipts_message", unique: true
    t.index ["installation_id"], name: "index_agent_control_report_receipts_on_installation_id"
    t.index ["mailbox_item_id"], name: "index_agent_control_report_receipts_on_mailbox_item_id"
  end

  create_table "agent_deployments", force: :cascade do |t|
    t.bigint "active_capability_snapshot_id"
    t.bigint "agent_installation_id", null: false
    t.boolean "auto_resume_eligible", default: false, null: false
    t.string "bootstrap_state", default: "pending", null: false
    t.string "control_activity_state", default: "offline", null: false
    t.datetime "created_at", null: false
    t.jsonb "endpoint_metadata", default: {}, null: false
    t.bigint "execution_environment_id", null: false
    t.string "fingerprint", null: false
    t.jsonb "health_metadata", default: {}, null: false
    t.string "health_status", default: "offline", null: false
    t.bigint "installation_id", null: false
    t.datetime "last_control_activity_at"
    t.datetime "last_health_check_at"
    t.datetime "last_heartbeat_at"
    t.string "machine_credential_digest", null: false
    t.string "protocol_version", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "realtime_link_state", default: "disconnected", null: false
    t.string "sdk_version", null: false
    t.string "unavailability_reason"
    t.datetime "updated_at", null: false
    t.index ["active_capability_snapshot_id"], name: "index_agent_deployments_on_active_capability_snapshot_id"
    t.index ["agent_installation_id"], name: "index_agent_deployments_on_agent_installation_id"
    t.index ["agent_installation_id"], name: "index_agent_deployments_on_agent_installation_id_active", unique: true, where: "((bootstrap_state)::text = 'active'::text)"
    t.index ["execution_environment_id"], name: "index_agent_deployments_on_execution_environment_id"
    t.index ["installation_id", "fingerprint"], name: "index_agent_deployments_on_installation_id_and_fingerprint", unique: true
    t.index ["installation_id"], name: "index_agent_deployments_on_installation_id"
    t.index ["machine_credential_digest"], name: "index_agent_deployments_on_machine_credential_digest", unique: true
    t.index ["public_id"], name: "index_agent_deployments_on_public_id", unique: true
  end

  create_table "agent_enrollments", force: :cascade do |t|
    t.bigint "agent_installation_id", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "installation_id", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_installation_id"], name: "index_agent_enrollments_on_agent_installation_id"
    t.index ["installation_id", "agent_installation_id", "expires_at"], name: "index_agent_enrollments_on_installation_agent_and_expiry"
    t.index ["installation_id"], name: "index_agent_enrollments_on_installation_id"
    t.index ["token_digest"], name: "index_agent_enrollments_on_token_digest", unique: true
  end

  create_table "agent_installations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.bigint "installation_id", null: false
    t.string "key", null: false
    t.string "lifecycle_state", default: "active", null: false
    t.bigint "owner_user_id"
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "global", null: false
    t.index ["installation_id", "key"], name: "index_agent_installations_on_installation_id_and_key", unique: true
    t.index ["installation_id", "visibility"], name: "index_agent_installations_on_installation_id_and_visibility"
    t.index ["installation_id"], name: "index_agent_installations_on_installation_id"
    t.index ["owner_user_id"], name: "index_agent_installations_on_owner_user_id"
    t.index ["public_id"], name: "index_agent_installations_on_public_id", unique: true
  end

  create_table "agent_task_runs", force: :cascade do |t|
    t.bigint "agent_installation_id", null: false
    t.integer "attempt_no", default: 1, null: false
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
    t.integer "expected_duration_seconds"
    t.datetime "finished_at"
    t.bigint "holder_agent_deployment_id"
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", default: "queued", null: false
    t.string "logical_work_id", null: false
    t.jsonb "progress_payload", default: {}, null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "started_at"
    t.string "task_kind", null: false
    t.jsonb "task_payload", default: {}, null: false
    t.jsonb "terminal_payload", default: {}, null: false
    t.bigint "turn_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workflow_node_id", null: false
    t.bigint "workflow_run_id", null: false
    t.index ["agent_installation_id"], name: "index_agent_task_runs_on_agent_installation_id"
    t.index ["conversation_id"], name: "index_agent_task_runs_on_conversation_id"
    t.index ["holder_agent_deployment_id"], name: "index_agent_task_runs_on_holder_agent_deployment_id"
    t.index ["installation_id"], name: "index_agent_task_runs_on_installation_id"
    t.index ["public_id"], name: "index_agent_task_runs_on_public_id", unique: true
    t.index ["turn_id"], name: "index_agent_task_runs_on_turn_id"
    t.index ["workflow_node_id"], name: "index_agent_task_runs_on_workflow_node_id"
    t.index ["workflow_run_id", "logical_work_id", "attempt_no"], name: "idx_agent_task_runs_work_attempt", unique: true
    t.index ["workflow_run_id"], name: "index_agent_task_runs_on_workflow_run_id"
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

  create_table "canonical_store_entries", force: :cascade do |t|
    t.bigint "canonical_store_snapshot_id", null: false
    t.bigint "canonical_store_value_id"
    t.datetime "created_at", null: false
    t.string "entry_kind", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value_bytesize"
    t.string "value_type"
    t.index ["canonical_store_snapshot_id", "key"], name: "idx_canonical_store_entries_snapshot_key", unique: true
    t.index ["canonical_store_snapshot_id"], name: "index_canonical_store_entries_on_canonical_store_snapshot_id"
    t.index ["canonical_store_value_id"], name: "index_canonical_store_entries_on_canonical_store_value_id"
    t.check_constraint "entry_kind::text = 'set'::text AND canonical_store_value_id IS NOT NULL AND value_type IS NOT NULL AND value_bytesize IS NOT NULL AND value_bytesize >= 0 AND value_bytesize <= 2097152 OR entry_kind::text = 'tombstone'::text AND canonical_store_value_id IS NULL AND value_type IS NULL AND value_bytesize IS NULL", name: "chk_canonical_store_entries_value_shape"
    t.check_constraint "entry_kind::text = ANY (ARRAY['set'::character varying, 'tombstone'::character varying]::text[])", name: "chk_canonical_store_entries_kind"
    t.check_constraint "octet_length(key::text) >= 1 AND octet_length(key::text) <= 128", name: "chk_canonical_store_entries_key_bytes"
  end

  create_table "canonical_store_references", force: :cascade do |t|
    t.bigint "canonical_store_snapshot_id", null: false
    t.datetime "created_at", null: false
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.datetime "updated_at", null: false
    t.index ["canonical_store_snapshot_id"], name: "idx_on_canonical_store_snapshot_id_6638a81780"
    t.index ["owner_type", "owner_id"], name: "idx_canonical_store_references_owner", unique: true
  end

  create_table "canonical_store_snapshots", force: :cascade do |t|
    t.bigint "base_snapshot_id"
    t.bigint "canonical_store_id", null: false
    t.datetime "created_at", null: false
    t.integer "depth", null: false
    t.string "snapshot_kind", null: false
    t.datetime "updated_at", null: false
    t.index ["base_snapshot_id"], name: "index_canonical_store_snapshots_on_base_snapshot_id"
    t.index ["canonical_store_id"], name: "index_canonical_store_snapshots_on_canonical_store_id"
    t.check_constraint "(snapshot_kind::text = ANY (ARRAY['root'::character varying, 'compaction'::character varying]::text[])) AND base_snapshot_id IS NULL AND depth = 0 OR snapshot_kind::text = 'write'::text AND base_snapshot_id IS NOT NULL AND depth >= 1", name: "chk_canonical_store_snapshots_shape"
    t.check_constraint "snapshot_kind::text = ANY (ARRAY['root'::character varying, 'write'::character varying, 'compaction'::character varying]::text[])", name: "chk_canonical_store_snapshots_kind"
  end

  create_table "canonical_store_values", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "payload_bytesize", null: false
    t.string "payload_sha256", null: false
    t.jsonb "typed_value_payload", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["payload_sha256"], name: "index_canonical_store_values_on_payload_sha256"
    t.check_constraint "payload_bytesize >= 0 AND payload_bytesize <= 2097152", name: "chk_canonical_store_values_payload_bytesize"
  end

  create_table "canonical_stores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.bigint "root_conversation_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["installation_id"], name: "index_canonical_stores_on_installation_id"
    t.index ["root_conversation_id"], name: "index_canonical_stores_on_root_conversation_id", unique: true
    t.index ["workspace_id"], name: "index_canonical_stores_on_workspace_id"
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

  create_table "capability_snapshots", force: :cascade do |t|
    t.bigint "agent_deployment_id", null: false
    t.jsonb "config_schema_snapshot", default: {}, null: false
    t.jsonb "conversation_override_schema_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "default_config_snapshot", default: {}, null: false
    t.jsonb "protocol_methods", default: [], null: false
    t.jsonb "tool_catalog", default: [], null: false
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["agent_deployment_id", "version"], name: "index_capability_snapshots_on_agent_deployment_id_and_version", unique: true
    t.index ["agent_deployment_id"], name: "index_capability_snapshots_on_agent_deployment_id"
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

  create_table "conversations", force: :cascade do |t|
    t.bigint "agent_deployment_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "deletion_state", default: "retained", null: false
    t.bigint "execution_environment_id", null: false
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
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["agent_deployment_id"], name: "index_conversations_on_agent_deployment_id"
    t.index ["execution_environment_id", "lifecycle_state"], name: "idx_conversations_environment_lifecycle"
    t.index ["execution_environment_id"], name: "index_conversations_on_execution_environment_id"
    t.index ["installation_id"], name: "index_conversations_on_installation_id"
    t.index ["parent_conversation_id"], name: "index_conversations_on_parent_conversation_id"
    t.index ["public_id"], name: "index_conversations_on_public_id", unique: true
    t.index ["workspace_id", "purpose", "lifecycle_state"], name: "idx_conversations_workspace_purpose_lifecycle"
    t.index ["workspace_id"], name: "index_conversations_on_workspace_id"
    t.check_constraint "deletion_state::text = 'retained'::text AND deleted_at IS NULL OR (deletion_state::text = ANY (ARRAY['pending_delete'::character varying, 'deleted'::character varying]::text[])) AND deleted_at IS NOT NULL", name: "chk_conversations_deleted_at_consistency"
    t.check_constraint "deletion_state::text = ANY (ARRAY['retained'::character varying, 'pending_delete'::character varying, 'deleted'::character varying]::text[])", name: "chk_conversations_deletion_state"
  end

  create_table "execution_environments", force: :cascade do |t|
    t.jsonb "capability_payload", default: {}, null: false
    t.jsonb "connection_metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "environment_fingerprint", null: false
    t.bigint "installation_id", null: false
    t.string "kind", default: "local", null: false
    t.string "lifecycle_state", default: "active", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.jsonb "tool_catalog", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["installation_id", "environment_fingerprint"], name: "idx_execution_environments_installation_fingerprint", unique: true
    t.index ["installation_id", "kind"], name: "index_execution_environments_on_installation_id_and_kind"
    t.index ["installation_id"], name: "index_execution_environments_on_installation_id"
    t.index ["public_id"], name: "index_execution_environments_on_public_id", unique: true
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
    t.bigint "conversation_id"
    t.integer "count_value"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "fact_key", null: false
    t.string "fact_kind", null: false
    t.bigint "human_interaction_request_id"
    t.bigint "installation_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.bigint "process_run_id"
    t.bigint "subagent_run_id"
    t.boolean "success"
    t.bigint "turn_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "workflow_node_key"
    t.bigint "workspace_id"
    t.index ["installation_id", "fact_kind", "fact_key"], name: "idx_execution_profile_facts_installation_kind_key"
    t.index ["installation_id", "occurred_at"], name: "idx_on_installation_id_occurred_at_361e402309"
    t.index ["installation_id"], name: "index_execution_profile_facts_on_installation_id"
    t.index ["user_id"], name: "index_execution_profile_facts_on_user_id"
    t.index ["workspace_id"], name: "index_execution_profile_facts_on_workspace_id"
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
    t.bigint "execution_environment_id", null: false
    t.integer "exit_status"
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
    t.index ["execution_environment_id", "lifecycle_state"], name: "idx_process_runs_environment_lifecycle"
    t.index ["execution_environment_id"], name: "index_process_runs_on_execution_environment_id"
    t.index ["installation_id"], name: "index_process_runs_on_installation_id"
    t.index ["origin_message_id"], name: "index_process_runs_on_origin_message_id"
    t.index ["public_id"], name: "index_process_runs_on_public_id", unique: true
    t.index ["turn_id"], name: "index_process_runs_on_turn_id"
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
    t.integer "max_concurrent_requests"
    t.string "provider_handle", null: false
    t.jsonb "selection_defaults", default: {}, null: false
    t.integer "throttle_limit"
    t.integer "throttle_period_seconds"
    t.datetime "updated_at", null: false
    t.index ["installation_id", "provider_handle"], name: "index_provider_policies_on_installation_id_and_provider_handle", unique: true
    t.index ["installation_id"], name: "index_provider_policies_on_installation_id"
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

  create_table "subagent_runs", force: :cascade do |t|
    t.string "batch_key"
    t.datetime "close_acknowledged_at"
    t.datetime "close_force_deadline_at"
    t.datetime "close_grace_deadline_at"
    t.string "close_outcome_kind"
    t.jsonb "close_outcome_payload", default: {}, null: false
    t.string "close_reason_kind"
    t.datetime "close_requested_at"
    t.string "close_state", default: "open", null: false
    t.string "coordination_key"
    t.datetime "created_at", null: false
    t.integer "depth", default: 0, null: false
    t.string "failure_reason"
    t.datetime "finished_at"
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", default: "running", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "parent_subagent_run_id"
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.string "requested_role_or_slot", null: false
    t.datetime "started_at", null: false
    t.bigint "terminal_summary_artifact_id"
    t.datetime "updated_at", null: false
    t.bigint "workflow_node_id", null: false
    t.bigint "workflow_run_id", null: false
    t.index ["installation_id"], name: "index_subagent_runs_on_installation_id"
    t.index ["parent_subagent_run_id"], name: "index_subagent_runs_on_parent_subagent_run_id"
    t.index ["public_id"], name: "index_subagent_runs_on_public_id", unique: true
    t.index ["terminal_summary_artifact_id"], name: "index_subagent_runs_on_terminal_summary_artifact_id"
    t.index ["workflow_node_id", "created_at"], name: "idx_subagent_runs_node_created"
    t.index ["workflow_node_id"], name: "index_subagent_runs_on_workflow_node_id"
    t.index ["workflow_run_id", "batch_key"], name: "idx_subagent_runs_run_batch"
    t.index ["workflow_run_id", "coordination_key"], name: "idx_subagent_runs_run_coordination"
    t.index ["workflow_run_id"], name: "index_subagent_runs_on_workflow_run_id"
  end

  create_table "turns", force: :cascade do |t|
    t.bigint "agent_deployment_id", null: false
    t.string "cancellation_reason_kind"
    t.datetime "cancellation_requested_at"
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "execution_snapshot_payload", default: {}, null: false
    t.string "external_event_key"
    t.string "idempotency_key"
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", null: false
    t.string "origin_kind", null: false
    t.jsonb "origin_payload", default: {}, null: false
    t.string "pinned_deployment_fingerprint", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.jsonb "resolved_config_snapshot", default: {}, null: false
    t.jsonb "resolved_model_selection_snapshot", default: {}, null: false
    t.bigint "selected_input_message_id"
    t.bigint "selected_output_message_id"
    t.integer "sequence", null: false
    t.string "source_ref_id"
    t.string "source_ref_type"
    t.datetime "updated_at", null: false
    t.index ["agent_deployment_id"], name: "index_turns_on_agent_deployment_id"
    t.index ["conversation_id", "sequence"], name: "index_turns_on_conversation_id_and_sequence", unique: true
    t.index ["conversation_id"], name: "index_turns_on_conversation_id"
    t.index ["installation_id"], name: "index_turns_on_installation_id"
    t.index ["public_id"], name: "index_turns_on_public_id", unique: true
    t.index ["selected_input_message_id"], name: "index_turns_on_selected_input_message_id"
    t.index ["selected_output_message_id"], name: "index_turns_on_selected_output_message_id"
    t.check_constraint "cancellation_reason_kind IS NULL AND cancellation_requested_at IS NULL OR cancellation_reason_kind IS NOT NULL AND cancellation_requested_at IS NOT NULL", name: "chk_turns_cancellation_pairing"
    t.check_constraint "cancellation_reason_kind IS NULL OR (cancellation_reason_kind::text = ANY (ARRAY['conversation_deleted'::character varying::text, 'conversation_archived'::character varying::text, 'turn_interrupted'::character varying::text]))", name: "chk_turns_cancellation_reason_kind"
  end

  create_table "usage_events", force: :cascade do |t|
    t.bigint "agent_deployment_id"
    t.bigint "agent_installation_id"
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
    t.string "provider_handle", null: false
    t.boolean "success", null: false
    t.bigint "turn_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "workflow_node_key"
    t.bigint "workspace_id"
    t.index ["agent_deployment_id"], name: "index_usage_events_on_agent_deployment_id"
    t.index ["agent_installation_id"], name: "index_usage_events_on_agent_installation_id"
    t.index ["installation_id", "occurred_at"], name: "index_usage_events_on_installation_id_and_occurred_at"
    t.index ["installation_id"], name: "index_usage_events_on_installation_id"
    t.index ["provider_handle", "model_ref"], name: "index_usage_events_on_provider_handle_and_model_ref"
    t.index ["user_id"], name: "index_usage_events_on_user_id"
    t.index ["workspace_id"], name: "index_usage_events_on_workspace_id"
  end

  create_table "usage_rollups", force: :cascade do |t|
    t.bigint "agent_deployment_id"
    t.bigint "agent_installation_id"
    t.string "bucket_key", null: false
    t.string "bucket_kind", null: false
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
    t.string "provider_handle", null: false
    t.integer "success_count", default: 0, null: false
    t.integer "total_latency_ms", default: 0, null: false
    t.bigint "turn_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "workflow_node_key"
    t.bigint "workspace_id"
    t.index ["agent_deployment_id"], name: "index_usage_rollups_on_agent_deployment_id"
    t.index ["agent_installation_id"], name: "index_usage_rollups_on_agent_installation_id"
    t.index ["installation_id", "bucket_kind", "bucket_key", "dimension_digest"], name: "idx_usage_rollups_installation_bucket_dimension", unique: true
    t.index ["installation_id"], name: "index_usage_rollups_on_installation_id"
    t.index ["user_id"], name: "index_usage_rollups_on_user_id"
    t.index ["workspace_id"], name: "index_usage_rollups_on_workspace_id"
  end

  create_table "user_agent_bindings", force: :cascade do |t|
    t.bigint "agent_installation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.jsonb "preferences", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["agent_installation_id"], name: "index_user_agent_bindings_on_agent_installation_id"
    t.index ["installation_id", "user_id"], name: "index_user_agent_bindings_on_installation_id_and_user_id"
    t.index ["installation_id"], name: "index_user_agent_bindings_on_installation_id"
    t.index ["user_id", "agent_installation_id"], name: "index_user_agent_bindings_on_user_id_and_agent_installation_id", unique: true
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
    t.jsonb "payload", default: {}, null: false
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
    t.bigint "to_node_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workflow_run_id", null: false
    t.index ["from_node_id"], name: "index_workflow_edges_on_from_node_id"
    t.index ["installation_id"], name: "index_workflow_edges_on_installation_id"
    t.index ["to_node_id"], name: "index_workflow_edges_on_to_node_id"
    t.index ["workflow_run_id", "from_node_id", "ordinal"], name: "idx_on_workflow_run_id_from_node_id_ordinal_2bc1936b9e", unique: true
    t.index ["workflow_run_id", "from_node_id", "to_node_id"], name: "idx_on_workflow_run_id_from_node_id_to_node_id_54f159bded", unique: true
    t.index ["workflow_run_id"], name: "index_workflow_edges_on_workflow_run_id"
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
    t.bigint "conversation_id"
    t.datetime "created_at", null: false
    t.string "decision_source", null: false
    t.bigint "installation_id", null: false
    t.string "intent_kind"
    t.jsonb "metadata", default: {}, null: false
    t.string "node_key", null: false
    t.string "node_type", null: false
    t.integer "ordinal", null: false
    t.string "presentation_policy"
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.integer "stage_index"
    t.integer "stage_position"
    t.bigint "turn_id"
    t.datetime "updated_at", null: false
    t.bigint "workflow_run_id", null: false
    t.bigint "workspace_id"
    t.bigint "yielding_workflow_node_id"
    t.index ["conversation_id"], name: "index_workflow_nodes_on_conversation_id"
    t.index ["installation_id"], name: "index_workflow_nodes_on_installation_id"
    t.index ["public_id"], name: "index_workflow_nodes_on_public_id", unique: true
    t.index ["turn_id"], name: "index_workflow_nodes_on_turn_id"
    t.index ["workflow_run_id", "node_key"], name: "index_workflow_nodes_on_workflow_run_id_and_node_key", unique: true
    t.index ["workflow_run_id", "ordinal"], name: "index_workflow_nodes_on_workflow_run_id_and_ordinal", unique: true
    t.index ["workflow_run_id", "stage_index", "stage_position"], name: "index_workflow_nodes_on_run_stage_order"
    t.index ["workflow_run_id"], name: "index_workflow_nodes_on_workflow_run_id"
    t.index ["workspace_id"], name: "index_workflow_nodes_on_workspace_id"
    t.index ["yielding_workflow_node_id"], name: "index_workflow_nodes_on_yielding_workflow_node_id"
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
    t.jsonb "resume_metadata", default: {}, null: false
    t.string "resume_policy"
    t.bigint "turn_id", null: false
    t.datetime "updated_at", null: false
    t.string "wait_reason_kind"
    t.jsonb "wait_reason_payload", default: {}, null: false
    t.string "wait_state", default: "ready", null: false
    t.datetime "waiting_since_at"
    t.bigint "workspace_id"
    t.index ["conversation_id"], name: "index_workflow_runs_on_conversation_id"
    t.index ["conversation_id"], name: "index_workflow_runs_on_conversation_id_active", unique: true, where: "((lifecycle_state)::text = 'active'::text)"
    t.index ["installation_id"], name: "index_workflow_runs_on_installation_id"
    t.index ["public_id"], name: "index_workflow_runs_on_public_id", unique: true
    t.index ["turn_id"], name: "index_workflow_runs_on_turn_id", unique: true
    t.index ["workspace_id"], name: "index_workflow_runs_on_workspace_id"
    t.check_constraint "cancellation_reason_kind IS NULL AND cancellation_requested_at IS NULL OR cancellation_reason_kind IS NOT NULL AND cancellation_requested_at IS NOT NULL", name: "chk_workflow_runs_cancellation_pairing"
    t.check_constraint "cancellation_reason_kind IS NULL OR (cancellation_reason_kind::text = ANY (ARRAY['conversation_deleted'::character varying::text, 'conversation_archived'::character varying::text, 'turn_interrupted'::character varying::text]))", name: "chk_workflow_runs_cancellation_reason_kind"
    t.check_constraint "resume_policy IS NULL OR resume_policy::text = 're_enter_agent'::text", name: "chk_workflow_runs_resume_policy"
  end

  create_table "workspaces", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.boolean "is_default", default: false, null: false
    t.string "name", null: false
    t.string "privacy", default: "private", null: false
    t.uuid "public_id", default: -> { "uuidv7()" }, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_agent_binding_id", null: false
    t.bigint "user_id", null: false
    t.index ["installation_id", "user_id"], name: "index_workspaces_on_installation_id_and_user_id"
    t.index ["installation_id"], name: "index_workspaces_on_installation_id"
    t.index ["public_id"], name: "index_workspaces_on_public_id", unique: true
    t.index ["user_agent_binding_id"], name: "index_workspaces_on_user_agent_binding_id"
    t.index ["user_agent_binding_id"], name: "index_workspaces_on_user_agent_binding_id_default", unique: true, where: "is_default"
    t.index ["user_id"], name: "index_workspaces_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_control_mailbox_items", "agent_deployments", column: "leased_to_agent_deployment_id"
  add_foreign_key "agent_control_mailbox_items", "agent_deployments", column: "target_agent_deployment_id"
  add_foreign_key "agent_control_mailbox_items", "agent_installations", column: "target_agent_installation_id"
  add_foreign_key "agent_control_mailbox_items", "agent_task_runs"
  add_foreign_key "agent_control_mailbox_items", "installations"
  add_foreign_key "agent_control_report_receipts", "agent_control_mailbox_items", column: "mailbox_item_id"
  add_foreign_key "agent_control_report_receipts", "agent_deployments"
  add_foreign_key "agent_control_report_receipts", "agent_task_runs"
  add_foreign_key "agent_control_report_receipts", "installations"
  add_foreign_key "agent_deployments", "agent_installations"
  add_foreign_key "agent_deployments", "capability_snapshots", column: "active_capability_snapshot_id"
  add_foreign_key "agent_deployments", "execution_environments"
  add_foreign_key "agent_deployments", "installations"
  add_foreign_key "agent_enrollments", "agent_installations"
  add_foreign_key "agent_enrollments", "installations"
  add_foreign_key "agent_installations", "installations"
  add_foreign_key "agent_installations", "users", column: "owner_user_id"
  add_foreign_key "agent_task_runs", "agent_deployments", column: "holder_agent_deployment_id"
  add_foreign_key "agent_task_runs", "agent_installations"
  add_foreign_key "agent_task_runs", "conversations"
  add_foreign_key "agent_task_runs", "installations"
  add_foreign_key "agent_task_runs", "turns"
  add_foreign_key "agent_task_runs", "workflow_nodes"
  add_foreign_key "agent_task_runs", "workflow_runs"
  add_foreign_key "audit_logs", "installations"
  add_foreign_key "canonical_store_entries", "canonical_store_snapshots"
  add_foreign_key "canonical_store_entries", "canonical_store_values"
  add_foreign_key "canonical_store_references", "canonical_store_snapshots"
  add_foreign_key "canonical_store_snapshots", "canonical_store_snapshots", column: "base_snapshot_id"
  add_foreign_key "canonical_store_snapshots", "canonical_stores"
  add_foreign_key "canonical_stores", "conversations", column: "root_conversation_id"
  add_foreign_key "canonical_stores", "installations"
  add_foreign_key "canonical_stores", "workspaces"
  add_foreign_key "canonical_variables", "canonical_variables", column: "superseded_by_id"
  add_foreign_key "canonical_variables", "conversations", column: "source_conversation_id"
  add_foreign_key "canonical_variables", "installations"
  add_foreign_key "canonical_variables", "turns", column: "source_turn_id"
  add_foreign_key "canonical_variables", "workflow_runs", column: "source_workflow_run_id"
  add_foreign_key "canonical_variables", "workspaces"
  add_foreign_key "capability_snapshots", "agent_deployments"
  add_foreign_key "conversation_close_operations", "conversations"
  add_foreign_key "conversation_close_operations", "installations"
  add_foreign_key "conversation_closures", "conversations", column: "ancestor_conversation_id"
  add_foreign_key "conversation_closures", "conversations", column: "descendant_conversation_id"
  add_foreign_key "conversation_closures", "installations"
  add_foreign_key "conversation_events", "conversations"
  add_foreign_key "conversation_events", "installations"
  add_foreign_key "conversation_events", "turns"
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
  add_foreign_key "conversations", "agent_deployments"
  add_foreign_key "conversations", "conversations", column: "parent_conversation_id"
  add_foreign_key "conversations", "execution_environments"
  add_foreign_key "conversations", "installations"
  add_foreign_key "conversations", "workspaces"
  add_foreign_key "execution_environments", "installations"
  add_foreign_key "execution_leases", "installations"
  add_foreign_key "execution_leases", "workflow_nodes"
  add_foreign_key "execution_leases", "workflow_runs"
  add_foreign_key "execution_profile_facts", "installations"
  add_foreign_key "execution_profile_facts", "users"
  add_foreign_key "execution_profile_facts", "workspaces"
  add_foreign_key "human_interaction_requests", "conversations"
  add_foreign_key "human_interaction_requests", "installations"
  add_foreign_key "human_interaction_requests", "turns"
  add_foreign_key "human_interaction_requests", "workflow_nodes"
  add_foreign_key "human_interaction_requests", "workflow_runs"
  add_foreign_key "invitations", "installations"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "message_attachments", "conversations"
  add_foreign_key "message_attachments", "installations"
  add_foreign_key "message_attachments", "message_attachments", column: "origin_attachment_id"
  add_foreign_key "message_attachments", "messages"
  add_foreign_key "message_attachments", "messages", column: "origin_message_id"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "installations"
  add_foreign_key "messages", "messages", column: "source_input_message_id"
  add_foreign_key "messages", "turns"
  add_foreign_key "process_runs", "conversations"
  add_foreign_key "process_runs", "execution_environments"
  add_foreign_key "process_runs", "installations"
  add_foreign_key "process_runs", "messages", column: "origin_message_id"
  add_foreign_key "process_runs", "turns"
  add_foreign_key "process_runs", "workflow_nodes"
  add_foreign_key "provider_credentials", "installations"
  add_foreign_key "provider_entitlements", "installations"
  add_foreign_key "provider_policies", "installations"
  add_foreign_key "publication_access_events", "installations"
  add_foreign_key "publication_access_events", "publications"
  add_foreign_key "publication_access_events", "users", column: "viewer_user_id"
  add_foreign_key "publications", "conversations"
  add_foreign_key "publications", "installations"
  add_foreign_key "publications", "users", column: "owner_user_id"
  add_foreign_key "sessions", "identities"
  add_foreign_key "sessions", "users"
  add_foreign_key "subagent_runs", "installations"
  add_foreign_key "subagent_runs", "subagent_runs", column: "parent_subagent_run_id"
  add_foreign_key "subagent_runs", "workflow_artifacts", column: "terminal_summary_artifact_id"
  add_foreign_key "subagent_runs", "workflow_nodes"
  add_foreign_key "subagent_runs", "workflow_runs"
  add_foreign_key "turns", "agent_deployments"
  add_foreign_key "turns", "conversations"
  add_foreign_key "turns", "installations"
  add_foreign_key "turns", "messages", column: "selected_input_message_id"
  add_foreign_key "turns", "messages", column: "selected_output_message_id"
  add_foreign_key "usage_events", "agent_deployments"
  add_foreign_key "usage_events", "agent_installations"
  add_foreign_key "usage_events", "installations"
  add_foreign_key "usage_events", "users"
  add_foreign_key "usage_events", "workspaces"
  add_foreign_key "usage_rollups", "agent_deployments"
  add_foreign_key "usage_rollups", "agent_installations"
  add_foreign_key "usage_rollups", "installations"
  add_foreign_key "usage_rollups", "users"
  add_foreign_key "usage_rollups", "workspaces"
  add_foreign_key "user_agent_bindings", "agent_installations"
  add_foreign_key "user_agent_bindings", "installations"
  add_foreign_key "user_agent_bindings", "users"
  add_foreign_key "users", "identities"
  add_foreign_key "users", "installations"
  add_foreign_key "workflow_artifacts", "conversations"
  add_foreign_key "workflow_artifacts", "installations"
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
  add_foreign_key "workflow_nodes", "installations"
  add_foreign_key "workflow_nodes", "turns"
  add_foreign_key "workflow_nodes", "workflow_nodes", column: "yielding_workflow_node_id"
  add_foreign_key "workflow_nodes", "workflow_runs"
  add_foreign_key "workflow_nodes", "workspaces"
  add_foreign_key "workflow_runs", "conversations"
  add_foreign_key "workflow_runs", "installations"
  add_foreign_key "workflow_runs", "turns"
  add_foreign_key "workflow_runs", "workspaces"
  add_foreign_key "workspaces", "installations"
  add_foreign_key "workspaces", "user_agent_bindings"
  add_foreign_key "workspaces", "users"
end
