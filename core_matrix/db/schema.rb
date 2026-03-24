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

ActiveRecord::Schema[8.2].define(version: 2026_03_24_090031) do
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

  create_table "agent_deployments", force: :cascade do |t|
    t.bigint "active_capability_snapshot_id"
    t.bigint "agent_installation_id", null: false
    t.boolean "auto_resume_eligible", default: false, null: false
    t.string "bootstrap_state", default: "pending", null: false
    t.datetime "created_at", null: false
    t.jsonb "endpoint_metadata", default: {}, null: false
    t.bigint "execution_environment_id", null: false
    t.string "fingerprint", null: false
    t.jsonb "health_metadata", default: {}, null: false
    t.string "health_status", default: "offline", null: false
    t.bigint "installation_id", null: false
    t.datetime "last_health_check_at"
    t.datetime "last_heartbeat_at"
    t.string "machine_credential_digest", null: false
    t.string "protocol_version", null: false
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
    t.datetime "updated_at", null: false
    t.string "visibility", default: "global", null: false
    t.index ["installation_id", "key"], name: "index_agent_installations_on_installation_id_and_key", unique: true
    t.index ["installation_id", "visibility"], name: "index_agent_installations_on_installation_id_and_visibility"
    t.index ["installation_id"], name: "index_agent_installations_on_installation_id"
    t.index ["owner_user_id"], name: "index_agent_installations_on_owner_user_id"
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
    t.datetime "created_at", null: false
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
    t.string "purpose", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["installation_id"], name: "index_conversations_on_installation_id"
    t.index ["parent_conversation_id"], name: "index_conversations_on_parent_conversation_id"
    t.index ["workspace_id", "purpose", "lifecycle_state"], name: "idx_conversations_workspace_purpose_lifecycle"
    t.index ["workspace_id"], name: "index_conversations_on_workspace_id"
  end

  create_table "execution_environments", force: :cascade do |t|
    t.jsonb "connection_metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.string "kind", default: "local", null: false
    t.string "lifecycle_state", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["installation_id", "kind"], name: "index_execution_environments_on_installation_id_and_kind"
    t.index ["installation_id"], name: "index_execution_environments_on_installation_id"
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
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_invitations_on_email"
    t.index ["installation_id"], name: "index_invitations_on_installation_id"
    t.index ["inviter_id"], name: "index_invitations_on_inviter_id"
    t.index ["token_digest"], name: "index_invitations_on_token_digest", unique: true
  end

  create_table "message_attachments", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.bigint "message_id", null: false
    t.bigint "origin_attachment_id"
    t.bigint "origin_message_id"
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_message_attachments_on_conversation_id"
    t.index ["installation_id"], name: "index_message_attachments_on_installation_id"
    t.index ["message_id"], name: "index_message_attachments_on_message_id"
    t.index ["origin_attachment_id"], name: "index_message_attachments_on_origin_attachment_id"
    t.index ["origin_message_id"], name: "index_message_attachments_on_origin_message_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "content", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.string "role", null: false
    t.string "slot", null: false
    t.bigint "turn_id", null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.integer "variant_index", default: 0, null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["installation_id"], name: "index_messages_on_installation_id"
    t.index ["turn_id", "slot", "variant_index"], name: "index_messages_on_turn_id_and_slot_and_variant_index", unique: true
    t.index ["turn_id"], name: "index_messages_on_turn_id"
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

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "identity_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["identity_id"], name: "index_sessions_on_identity_id"
    t.index ["token_digest"], name: "index_sessions_on_token_digest", unique: true
    t.index ["user_id", "expires_at"], name: "index_sessions_on_user_id_and_expires_at"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "turns", force: :cascade do |t|
    t.bigint "agent_deployment_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "external_event_key"
    t.string "idempotency_key"
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", null: false
    t.string "origin_kind", null: false
    t.jsonb "origin_payload", default: {}, null: false
    t.string "pinned_deployment_fingerprint", null: false
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
    t.index ["selected_input_message_id"], name: "index_turns_on_selected_input_message_id"
    t.index ["selected_output_message_id"], name: "index_turns_on_selected_output_message_id"
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
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.index ["identity_id"], name: "index_users_on_identity_id", unique: true
    t.index ["installation_id", "role"], name: "index_users_on_installation_id_and_role"
    t.index ["installation_id"], name: "index_users_on_installation_id"
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

  create_table "workflow_nodes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "decision_source", null: false
    t.bigint "installation_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "node_key", null: false
    t.string "node_type", null: false
    t.integer "ordinal", null: false
    t.datetime "updated_at", null: false
    t.bigint "workflow_run_id", null: false
    t.index ["installation_id"], name: "index_workflow_nodes_on_installation_id"
    t.index ["workflow_run_id", "node_key"], name: "index_workflow_nodes_on_workflow_run_id_and_node_key", unique: true
    t.index ["workflow_run_id", "ordinal"], name: "index_workflow_nodes_on_workflow_run_id_and_ordinal", unique: true
    t.index ["workflow_run_id"], name: "index_workflow_nodes_on_workflow_run_id"
  end

  create_table "workflow_runs", force: :cascade do |t|
    t.string "blocking_resource_id"
    t.string "blocking_resource_type"
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.string "lifecycle_state", default: "active", null: false
    t.bigint "turn_id", null: false
    t.datetime "updated_at", null: false
    t.string "wait_reason_kind"
    t.jsonb "wait_reason_payload", default: {}, null: false
    t.string "wait_state", default: "ready", null: false
    t.datetime "waiting_since_at"
    t.index ["conversation_id"], name: "index_workflow_runs_on_conversation_id"
    t.index ["conversation_id"], name: "index_workflow_runs_on_conversation_id_active", unique: true, where: "((lifecycle_state)::text = 'active'::text)"
    t.index ["installation_id"], name: "index_workflow_runs_on_installation_id"
    t.index ["turn_id"], name: "index_workflow_runs_on_turn_id", unique: true
  end

  create_table "workspaces", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "installation_id", null: false
    t.boolean "is_default", default: false, null: false
    t.string "name", null: false
    t.string "privacy", default: "private", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_agent_binding_id", null: false
    t.bigint "user_id", null: false
    t.index ["installation_id", "user_id"], name: "index_workspaces_on_installation_id_and_user_id"
    t.index ["installation_id"], name: "index_workspaces_on_installation_id"
    t.index ["user_agent_binding_id"], name: "index_workspaces_on_user_agent_binding_id"
    t.index ["user_agent_binding_id"], name: "index_workspaces_on_user_agent_binding_id_default", unique: true, where: "is_default"
    t.index ["user_id"], name: "index_workspaces_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_deployments", "agent_installations"
  add_foreign_key "agent_deployments", "capability_snapshots", column: "active_capability_snapshot_id"
  add_foreign_key "agent_deployments", "execution_environments"
  add_foreign_key "agent_deployments", "installations"
  add_foreign_key "agent_enrollments", "agent_installations"
  add_foreign_key "agent_enrollments", "installations"
  add_foreign_key "agent_installations", "installations"
  add_foreign_key "agent_installations", "users", column: "owner_user_id"
  add_foreign_key "audit_logs", "installations"
  add_foreign_key "capability_snapshots", "agent_deployments"
  add_foreign_key "conversation_closures", "conversations", column: "ancestor_conversation_id"
  add_foreign_key "conversation_closures", "conversations", column: "descendant_conversation_id"
  add_foreign_key "conversation_closures", "installations"
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
  add_foreign_key "conversations", "conversations", column: "parent_conversation_id"
  add_foreign_key "conversations", "installations"
  add_foreign_key "conversations", "workspaces"
  add_foreign_key "execution_environments", "installations"
  add_foreign_key "execution_profile_facts", "installations"
  add_foreign_key "execution_profile_facts", "users"
  add_foreign_key "execution_profile_facts", "workspaces"
  add_foreign_key "invitations", "installations"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "message_attachments", "conversations"
  add_foreign_key "message_attachments", "installations"
  add_foreign_key "message_attachments", "message_attachments", column: "origin_attachment_id"
  add_foreign_key "message_attachments", "messages"
  add_foreign_key "message_attachments", "messages", column: "origin_message_id"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "installations"
  add_foreign_key "messages", "turns"
  add_foreign_key "provider_credentials", "installations"
  add_foreign_key "provider_entitlements", "installations"
  add_foreign_key "provider_policies", "installations"
  add_foreign_key "sessions", "identities"
  add_foreign_key "sessions", "users"
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
  add_foreign_key "workflow_edges", "installations"
  add_foreign_key "workflow_edges", "workflow_nodes", column: "from_node_id"
  add_foreign_key "workflow_edges", "workflow_nodes", column: "to_node_id"
  add_foreign_key "workflow_edges", "workflow_runs"
  add_foreign_key "workflow_nodes", "installations"
  add_foreign_key "workflow_nodes", "workflow_runs"
  add_foreign_key "workflow_runs", "conversations"
  add_foreign_key "workflow_runs", "installations"
  add_foreign_key "workflow_runs", "turns"
  add_foreign_key "workspaces", "installations"
  add_foreign_key "workspaces", "user_agent_bindings"
  add_foreign_key "workspaces", "users"
end
