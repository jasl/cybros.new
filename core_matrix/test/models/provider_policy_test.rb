require "test_helper"

class ProviderPolicyTest < ActiveSupport::TestCase
  test "supports enablement concurrency and throttling fields" do
    policy = ProviderPolicy.create!(
      installation: create_installation!,
      provider_handle: "openai",
      enabled: false,
      max_concurrent_requests: 2,
      throttle_limit: 60,
      throttle_period_seconds: 60,
      selection_defaults: {}
    )

    assert_not policy.enabled?
    assert_equal 2, policy.max_concurrent_requests
    assert_equal 60, policy.throttle_limit
    assert_equal 60, policy.throttle_period_seconds
  end

  test "does not validate provider handle membership in the static catalog" do
    policy = ProviderPolicy.new(
      installation: create_installation!,
      provider_handle: "unknown_provider",
      enabled: true,
      selection_defaults: {}
    )

    assert policy.valid?
  end
end
