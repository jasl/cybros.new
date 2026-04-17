require "test_helper"

module ProviderAuthorizationSessions
end

class ProviderAuthorizationSessions::PollTest < ActiveSupport::TestCase
  test "persists oauth credential material and marks the session completed when device flow authorizes" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    authorization_session = ProviderAuthorizationSession.issue!(
      installation: installation,
      provider_handle: "codex_subscription",
      issued_by_user: actor,
      device_auth_id: "deviceauth_123",
      user_code: "ABCD-EFGH",
      verification_uri: "https://auth.openai.com/codex/device",
      poll_interval_seconds: 5,
      expires_at: 15.minutes.from_now
    )

    result = ProviderAuthorizationSessions::Poll.call(
      installation: installation,
      provider_handle: "codex_subscription",
      device_flow_poll: lambda do |**_kwargs|
        {
          status: :authorized,
          tokens: {
            "access_token" => "access-token-1",
            "refresh_token" => "refresh-token-1",
            "expires_at" => 2.hours.from_now,
          },
        }
      end
    )

    credential = ProviderCredential.find_by!(
      installation: installation,
      provider_handle: "codex_subscription",
      credential_kind: "oauth_codex"
    )

    assert_equal :authorized, result.fetch(:status)
    assert_equal "access-token-1", credential.access_token
    assert_equal "refresh-token-1", credential.refresh_token
    assert_nil credential.refresh_failed_at
    assert_nil credential.refresh_failure_reason

    assert_equal "completed", authorization_session.reload.status
    assert_not_nil authorization_session.completed_at
  end
end
