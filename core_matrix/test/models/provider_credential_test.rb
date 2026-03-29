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
end
