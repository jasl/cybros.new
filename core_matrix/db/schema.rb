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

ActiveRecord::Schema[8.2].define(version: 2026_03_24_090012) do
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
  add_foreign_key "execution_environments", "installations"
  add_foreign_key "invitations", "installations"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "sessions", "identities"
  add_foreign_key "sessions", "users"
  add_foreign_key "user_agent_bindings", "agent_installations"
  add_foreign_key "user_agent_bindings", "installations"
  add_foreign_key "user_agent_bindings", "users"
  add_foreign_key "users", "identities"
  add_foreign_key "users", "installations"
  add_foreign_key "workspaces", "installations"
  add_foreign_key "workspaces", "user_agent_bindings"
  add_foreign_key "workspaces", "users"
end
