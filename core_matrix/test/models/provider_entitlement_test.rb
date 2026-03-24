require "test_helper"

class ProviderEntitlementTest < ActiveSupport::TestCase
  test "supports rolling five-hour entitlement windows" do
    entitlement = ProviderEntitlement.create!(
      installation: create_installation!,
      provider_handle: "codex_subscription",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: true,
      metadata: {}
    )

    assert entitlement.rolling_five_hours?
    assert_equal 5.hours.to_i, entitlement.window_seconds
  end

  test "rejects unknown provider handles" do
    entitlement = ProviderEntitlement.new(
      installation: create_installation!,
      provider_handle: "unknown_provider",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: true,
      metadata: {}
    )

    assert_not entitlement.valid?
    assert_includes entitlement.errors[:provider_handle], "must exist in the provider catalog"
  end
end
