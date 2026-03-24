require "test_helper"

class ProviderGovernanceFlowTest < ActionDispatch::IntegrationTest
  test "credential entitlement and policy services persist against catalog-backed provider handles and audit each mutation" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")

    credential = ProviderCredentials::UpsertSecret.call(
      installation: installation,
      actor: actor,
      provider_handle: "openai",
      credential_kind: "api_key",
      secret: "sk-live-123",
      metadata: {}
    )
    entitlement = ProviderEntitlements::Upsert.call(
      installation: installation,
      actor: actor,
      provider_handle: "codex_subscription",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      quota_limit: 200_000,
      active: true,
      metadata: {}
    )
    policy = ProviderPolicies::Upsert.call(
      installation: installation,
      actor: actor,
      provider_handle: "openai",
      enabled: true,
      max_concurrent_requests: 2,
      throttle_limit: 60,
      throttle_period_seconds: 60,
      selection_defaults: {}
    )

    assert_equal installation, credential.installation
    assert_equal installation, entitlement.installation
    assert_equal installation, policy.installation
    assert_equal 3, AuditLog.where(installation: installation).where(action: [
      "provider_credential.upserted",
      "provider_entitlement.upserted",
      "provider_policy.upserted",
    ]).count
  end
end
