require "test_helper"

class AppApiAdminAuditEntriesTest < ActionDispatch::IntegrationTest
  test "lists recent human audit entries using public ids and excludes system records" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin", display_name: "Ops Admin")
    session = create_session!(user: admin)
    provider_policy = ProviderPolicy.create!(
      installation: installation,
      provider_handle: "openai",
      enabled: true,
      selection_defaults: {}
    )
    human_entry = AuditLog.record!(
      installation: installation,
      actor: admin,
      action: "provider_policy.upserted",
      subject: provider_policy,
      metadata: { "provider_handle" => "openai" }
    )
    AuditLog.record!(
      installation: installation,
      actor: nil,
      action: "provider_credential.refreshed",
      subject: nil,
      metadata: { "provider_handle" => "codex_subscription" }
    )

    get "/app_api/admin/audit_entries", headers: app_api_headers(session.plaintext_token)

    assert_response :success

    response_body = response.parsed_body
    assert_equal "admin_audit_entry_index", response_body.fetch("method_id")
    entries = response_body.fetch("audit_entries")
    assert_equal [human_entry.public_id], entries.map { |entry| entry.fetch("audit_entry_id") }
    assert_equal "Ops Admin", entries.first.dig("actor", "display_name")
    assert_equal admin.public_id, entries.first.dig("actor", "actor_id")
    assert_equal "provider_policy.upserted", entries.first.fetch("action")
    assert_equal "ProviderPolicy", entries.first.dig("subject", "subject_type")
    refute_includes response.body, %("#{human_entry.id}")
  end

  test "rejects non-admin access to audit entries" do
    installation = create_installation!
    member = create_user!(installation: installation, role: "member")
    session = create_session!(user: member)

    get "/app_api/admin/audit_entries", headers: app_api_headers(session.plaintext_token)

    assert_response :forbidden
    assert_equal "admin access is required", response.parsed_body.fetch("error")
  end
end
