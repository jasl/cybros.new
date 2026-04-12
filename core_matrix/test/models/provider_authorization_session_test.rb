require "test_helper"

class ProviderAuthorizationSessionTest < ActiveSupport::TestCase
  test "issues a plaintext state token and encrypts the pkce verifier" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")

    authorization_session = ProviderAuthorizationSession.issue!(
      installation: installation,
      provider_handle: "codex_subscription",
      issued_by_user: actor,
      expires_at: 15.minutes.from_now
    )

    assert authorization_session.matches_state?(authorization_session.plaintext_state)
    assert_equal "pending", authorization_session.status
    assert_equal "codex_subscription", authorization_session.provider_handle
    assert authorization_session.encrypted_attribute?(:pkce_verifier)
    assert_not_equal authorization_session.plaintext_pkce_verifier, authorization_session.ciphertext_for(:pkce_verifier)
  end
end
