require "test_helper"

module ProviderAuthorizationSessions
end

class ProviderAuthorizationSessions::IssueTest < ActiveSupport::TestCase
  test "issues a codex subscription device flow session" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    expires_at = 15.minutes.from_now.change(usec: 0)

    result = ProviderAuthorizationSessions::Issue.call(
      installation: installation,
      actor: actor,
      provider_handle: "codex_subscription",
      device_flow_start: lambda do
        {
          "device_auth_id" => "deviceauth_123",
          "user_code" => "ABCD-EFGH",
          "verification_uri" => "https://auth.openai.com/codex/device",
          "interval" => 5,
          "expires_at" => expires_at.iso8601,
        }
      end
    )

    authorization_session = result.fetch(:authorization_session)

    assert_equal "codex_subscription", authorization_session.provider_handle
    assert_equal "deviceauth_123", authorization_session.device_auth_id
    assert_equal "ABCD-EFGH", authorization_session.user_code
    assert_equal "https://auth.openai.com/codex/device", authorization_session.verification_uri
    assert_equal 5, authorization_session.poll_interval_seconds
    assert_equal expires_at, authorization_session.expires_at

    audit_log = AuditLog.find_by!(action: "provider_authorization_session.issued")
    assert_equal actor, audit_log.actor
    assert_equal authorization_session, audit_log.subject
  end
end
