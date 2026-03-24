require "test_helper"

class ProviderPolicies::UpsertTest < ActiveSupport::TestCase
  test "creates and updates provider policies through an audited service boundary" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")

    policy = ProviderPolicies::Upsert.call(
      installation: installation,
      actor: actor,
      provider_handle: "openai",
      enabled: true,
      max_concurrent_requests: 2,
      throttle_limit: 60,
      throttle_period_seconds: 60,
      selection_defaults: { "interactive" => "role:main" }
    )

    updated = ProviderPolicies::Upsert.call(
      installation: installation,
      actor: actor,
      provider_handle: "openai",
      enabled: false,
      max_concurrent_requests: 1,
      throttle_limit: 30,
      throttle_period_seconds: 60,
      selection_defaults: { "interactive" => "candidate:openai/gpt-5.3-chat-latest" }
    )

    assert_equal policy.id, updated.id
    assert_equal 1, ProviderPolicy.count
    assert_not updated.enabled?
    assert_equal 1, updated.max_concurrent_requests
    assert_equal 30, updated.throttle_limit

    assert_equal 2, AuditLog.where(action: "provider_policy.upserted").count
  end
end
