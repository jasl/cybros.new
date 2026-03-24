require "test_helper"

class ProviderEntitlements::UpsertTest < ActiveSupport::TestCase
  test "persists provider entitlements against catalog keys and derives rolling five-hour windows" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")

    entitlement = ProviderEntitlements::Upsert.call(
      installation: installation,
      actor: actor,
      provider_handle: "codex_subscription",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      quota_limit: 200_000,
      active: true,
      metadata: { "source" => "subscription" }
    )

    assert_equal installation, entitlement.installation
    assert_equal "codex_subscription", entitlement.provider_handle
    assert_equal "shared_window", entitlement.entitlement_key
    assert entitlement.rolling_five_hours?
    assert_equal 5.hours.to_i, entitlement.window_seconds

    audit_log = AuditLog.find_by!(action: "provider_entitlement.upserted")
    assert_equal actor, audit_log.actor
    assert_equal entitlement, audit_log.subject
    assert_equal "codex_subscription", audit_log.metadata["provider_handle"]
    assert_equal "shared_window", audit_log.metadata["entitlement_key"]
  end

  test "rejects entitlements for unknown provider handles" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")

    assert_raises(ActiveRecord::RecordInvalid) do
      ProviderEntitlements::Upsert.call(
        installation: installation,
        actor: actor,
        provider_handle: "unknown_provider",
        entitlement_key: "shared_window",
        window_kind: "rolling_five_hours",
        quota_limit: 200_000,
        active: true,
        metadata: {}
      )
    end
  end

  test "rejects unknown entitlement window kinds with validation errors" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")

    assert_raises(ActiveRecord::RecordInvalid) do
      ProviderEntitlements::Upsert.call(
        installation: installation,
        actor: actor,
        provider_handle: "codex_subscription",
        entitlement_key: "shared_window",
        window_kind: "unknown_window",
        quota_limit: 200_000,
        active: true,
        metadata: {}
      )
    end
  end
end
