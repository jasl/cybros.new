require "test_helper"

module ProviderAuthorizationSessions
end

class ProviderAuthorizationSessions::IssueTest < ActiveSupport::TestCase
  test "issues a codex subscription authorization session and returns an authorization url" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")

    result = ProviderAuthorizationSessions::Issue.call(
      installation: installation,
      actor: actor,
      provider_handle: "codex_subscription",
      redirect_uri: "http://localhost:3000/app_api/admin/llm_providers/codex_subscription/authorization/callback",
      issuer_base_url: "https://auth.example.test",
      client_id: "codex-client-123"
    )

    authorization_session = result.fetch(:authorization_session)
    authorization_url = result.fetch(:authorization_url)

    assert_equal "codex_subscription", authorization_session.provider_handle
    assert authorization_session.matches_state?(authorization_session.plaintext_state)
    assert_match(%r{\Ahttps://auth\.example\.test/}, authorization_url)
    assert_includes authorization_url, "state="
    assert_includes authorization_url, "code_challenge="

    audit_log = AuditLog.find_by!(action: "provider_authorization_session.issued")
    assert_equal actor, audit_log.actor
    assert_equal authorization_session, audit_log.subject
  end
end
