require "test_helper"

class ProviderAuthorizationSessionTest < ActiveSupport::TestCase
  test "issues a device flow session and encrypts the device auth id" do
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

    assert_equal "pending", authorization_session.status
    assert_equal "codex_subscription", authorization_session.provider_handle
    assert_equal "ABCD-EFGH", authorization_session.user_code
    assert_equal "https://auth.openai.com/codex/device", authorization_session.verification_uri
    assert_equal 5, authorization_session.poll_interval_seconds
    assert authorization_session.encrypted_attribute?(:device_auth_id)
    assert_not_equal "deviceauth_123", authorization_session.ciphertext_for(:device_auth_id)
  end
end
