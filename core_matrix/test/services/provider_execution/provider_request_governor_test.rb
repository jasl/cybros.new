require "test_helper"

class ProviderExecution::ProviderRequestGovernorTest < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
  end

  test "admits requests below the configured concurrency limit" do
    installation = create_installation!
    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation)

    decision = ProviderExecution::ProviderRequestGovernor.acquire(
      installation: installation,
      provider_handle: "openai",
      effective_catalog: effective_catalog,
      cache: @cache
    )

    assert decision.allowed?
    assert decision.lease_token.present?
    assert_nil decision.reason
  ensure
    ProviderExecution::ProviderRequestGovernor.release(
      installation: installation,
      provider_handle: "openai",
      effective_catalog: effective_catalog,
      cache: @cache,
      lease_token: decision&.lease_token
    )
  end

  test "blocks when max concurrent requests is exhausted" do
    installation = create_installation!
    ProviderPolicy.create!(
      installation: installation,
      provider_handle: "openai",
      enabled: true,
      max_concurrent_requests: 1,
      selection_defaults: {}
    )
    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation)

    first_decision = ProviderExecution::ProviderRequestGovernor.acquire(
      installation: installation,
      provider_handle: "openai",
      effective_catalog: effective_catalog,
      cache: @cache
    )
    blocked_decision = ProviderExecution::ProviderRequestGovernor.acquire(
      installation: installation,
      provider_handle: "openai",
      effective_catalog: effective_catalog,
      cache: @cache
    )

    assert first_decision.allowed?
    assert blocked_decision.blocked?
    assert_equal "max_concurrent_requests", blocked_decision.reason
    assert_operator blocked_decision.retry_at, :>, Time.current
  ensure
    ProviderExecution::ProviderRequestGovernor.release(
      installation: installation,
      provider_handle: "openai",
      effective_catalog: effective_catalog,
      cache: @cache,
      lease_token: first_decision&.lease_token
    )
  end

  test "records cooldown after an upstream rate limit" do
    installation = create_installation!
    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation)

    ProviderExecution::ProviderRequestGovernor.record_rate_limit!(
      installation: installation,
      provider_handle: "openai",
      effective_catalog: effective_catalog,
      cache: @cache,
      retry_after: 30
    )

    decision = ProviderExecution::ProviderRequestGovernor.acquire(
      installation: installation,
      provider_handle: "openai",
      effective_catalog: effective_catalog,
      cache: @cache
    )

    assert decision.blocked?
    assert_equal "cooldown", decision.reason
    assert_operator decision.retry_at, :>=, 29.seconds.from_now
  end

  test "renew keeps an active lease past its original expiry" do
    installation = create_installation!
    ProviderPolicy.create!(
      installation: installation,
      provider_handle: "openai",
      enabled: true,
      max_concurrent_requests: 1,
      selection_defaults: {}
    )
    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation)
    started_at = Time.zone.parse("2026-04-01 00:00:00 UTC")

    first_decision = ProviderExecution::ProviderRequestGovernor.acquire(
      installation: installation,
      provider_handle: "openai",
      effective_catalog: effective_catalog,
      cache: @cache,
      now: started_at,
      lease_ttl_seconds: 10
    )

    ProviderExecution::ProviderRequestGovernor.renew(
      installation: installation,
      provider_handle: "openai",
      effective_catalog: effective_catalog,
      cache: @cache,
      lease_token: first_decision.lease_token,
      now: started_at + 9.seconds,
      lease_ttl_seconds: 10
    )

    blocked_decision = ProviderExecution::ProviderRequestGovernor.acquire(
      installation: installation,
      provider_handle: "openai",
      effective_catalog: effective_catalog,
      cache: @cache,
      now: started_at + 11.seconds,
      lease_ttl_seconds: 10
    )

    assert first_decision.allowed?
    assert blocked_decision.blocked?
    assert_equal "max_concurrent_requests", blocked_decision.reason
  ensure
    ProviderExecution::ProviderRequestGovernor.release(
      installation: installation,
      provider_handle: "openai",
      effective_catalog: effective_catalog,
      cache: @cache,
      lease_token: first_decision&.lease_token,
      now: started_at + 11.seconds
    )
  end
end
