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

  test "rejects unknown provider handles" do
    credential = ProviderCredential.new(
      installation: create_installation!,
      provider_handle: "unknown_provider",
      credential_kind: "api_key",
      secret: "sk-live-123",
      metadata: {}
    )

    assert_not credential.valid?
    assert_includes credential.errors[:provider_handle], "must exist in the provider catalog"
  end
end
