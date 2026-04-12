require "test_helper"

module ProviderAuthorizationSessions
end

class ProviderAuthorizationSessions::CompleteCodexCallbackTest < ActiveSupport::TestCase
  test "persists oauth credential material and marks the session completed" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    authorization_session = ProviderAuthorizationSession.issue!(
      installation: installation,
      provider_handle: "codex_subscription",
      issued_by_user: actor,
      expires_at: 15.minutes.from_now
    )

    credential = ProviderAuthorizationSessions::CompleteCodexCallback.call(
      state: authorization_session.plaintext_state,
      code: "oauth-code-123",
      token_exchange: ->(**_kwargs) do
        {
          access_token: "access-token-1",
          refresh_token: "refresh-token-1",
          expires_at: 2.hours.from_now,
        }
      end
    )

    assert_equal "codex_subscription", credential.provider_handle
    assert_equal "oauth_codex", credential.credential_kind
    assert_equal "access-token-1", credential.access_token
    assert_equal "refresh-token-1", credential.refresh_token
    assert_nil credential.refresh_failed_at
    assert_nil credential.refresh_failure_reason

    assert_equal "completed", authorization_session.reload.status
    assert_not_nil authorization_session.completed_at
  end
end
