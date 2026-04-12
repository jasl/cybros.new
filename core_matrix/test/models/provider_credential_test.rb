require "test_helper"

class ProviderCredentialTest < ActiveSupport::TestCase
  test "encrypts the secret while preserving plaintext access" do
    credential = ProviderCredential.create!(
      installation: create_installation!,
      provider_handle: "openai",
      credential_kind: "api_key",
      secret: "sk-live-123",
      metadata: {},
      last_rotated_at: Time.current
    )

    assert_equal "sk-live-123", credential.secret
    assert credential.encrypted_attribute?(:secret)
    assert_not_equal "sk-live-123", credential.ciphertext_for(:secret)
  end

  test "does not validate provider handle membership in the static catalog" do
    credential = ProviderCredential.new(
      installation: create_installation!,
      provider_handle: "unknown_provider",
      credential_kind: "api_key",
      secret: "sk-live-123",
      metadata: {},
      last_rotated_at: Time.current
    )

    assert credential.valid?
  end

  test "oauth codex credentials encrypt oauth token material without requiring secret" do
    credential = ProviderCredential.create!(
      installation: create_installation!,
      provider_handle: "codex_subscription",
      credential_kind: "oauth_codex",
      access_token: "access-token-123",
      refresh_token: "refresh-token-456",
      expires_at: 2.hours.from_now,
      metadata: {},
      last_rotated_at: Time.current
    )

    assert_equal "access-token-123", credential.access_token
    assert_equal "refresh-token-456", credential.refresh_token
    assert credential.encrypted_attribute?(:access_token)
    assert credential.encrypted_attribute?(:refresh_token)
    assert_not_equal "access-token-123", credential.ciphertext_for(:access_token)
    assert_not_equal "refresh-token-456", credential.ciphertext_for(:refresh_token)
  end
end
