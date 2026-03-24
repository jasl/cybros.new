require "test_helper"

class ProviderCredentials::UpsertSecretTest < ActiveSupport::TestCase
  test "persists encrypted credential material against a catalog provider and audits the change" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")

    freeze_time do
      credential = ProviderCredentials::UpsertSecret.call(
        installation: installation,
        actor: actor,
        provider_handle: "openai",
        credential_kind: "api_key",
        secret: "sk-initial",
        metadata: { "label" => "primary" }
      )

      assert_equal installation, credential.installation
      assert_equal "openai", credential.provider_handle
      assert_equal "api_key", credential.credential_kind
      assert_equal "sk-initial", credential.secret
      assert_equal Time.current, credential.last_rotated_at

      audit_log = AuditLog.find_by!(action: "provider_credential.upserted")
      assert_equal actor, audit_log.actor
      assert_equal credential, audit_log.subject
      assert_equal "openai", audit_log.metadata["provider_handle"]
      assert_equal "api_key", audit_log.metadata["credential_kind"]
    end
  end

  test "updates the existing provider credential instead of duplicating it" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")

    original = ProviderCredentials::UpsertSecret.call(
      installation: installation,
      actor: actor,
      provider_handle: "openai",
      credential_kind: "api_key",
      secret: "sk-initial",
      metadata: {}
    )

    updated = ProviderCredentials::UpsertSecret.call(
      installation: installation,
      actor: actor,
      provider_handle: "openai",
      credential_kind: "api_key",
      secret: "sk-rotated",
      metadata: { "label" => "rotated" }
    )

    assert_equal original.id, updated.id
    assert_equal 1, ProviderCredential.count
    assert_equal "sk-rotated", updated.secret
    assert_equal "rotated", updated.metadata["label"]
  end
end
