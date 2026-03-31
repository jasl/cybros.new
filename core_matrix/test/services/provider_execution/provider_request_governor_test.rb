require "test_helper"

class ProviderExecution::ProviderRequestGovernorTest < ActiveSupport::TestCase
  test "admits requests below the configured concurrency limit" do
    installation = create_installation!
    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation)

    decision = ProviderExecution::ProviderRequestGovernor.acquire(
      installation: installation,
      provider_handle: "openai",
      effective_catalog: effective_catalog
    )

    assert decision.allowed?
    assert decision.lease_token.present?
    assert_nil decision.reason
  ensure
    ProviderExecution::ProviderRequestGovernor.release(
      installation: installation,
      provider_handle: "openai",
      effective_catalog: effective_catalog,
      lease_token: decision&.lease_token
    )
  end

  test "blocks when max concurrent requests is exhausted" do
    installation = create_installation!
    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation)

    first_decision = ProviderExecution::ProviderRequestGovernor.acquire(
      installation: installation,
      provider_handle: "local",
      effective_catalog: effective_catalog
    )
    blocked_decision = ProviderExecution::ProviderRequestGovernor.acquire(
      installation: installation,
      provider_handle: "local",
      effective_catalog: effective_catalog
    )

    assert first_decision.allowed?
    assert blocked_decision.blocked?
    assert_equal "max_concurrent_requests", blocked_decision.reason
    assert_operator blocked_decision.retry_at, :>, Time.current
  ensure
    ProviderExecution::ProviderRequestGovernor.release(
      installation: installation,
      provider_handle: "local",
      effective_catalog: effective_catalog,
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
      retry_after: 30
    )

    decision = ProviderExecution::ProviderRequestGovernor.acquire(
      installation: installation,
      provider_handle: "openai",
      effective_catalog: effective_catalog
    )

    assert decision.blocked?
    assert_equal "cooldown", decision.reason
    assert_operator decision.retry_at, :>=, 29.seconds.from_now

    control = ProviderRequestControl.find_by!(
      installation: installation,
      provider_handle: "openai"
    )
    assert_operator control.cooldown_until, :>=, 29.seconds.from_now
    assert_equal "upstream_rate_limit", control.last_rate_limit_reason
  end

  test "renew keeps an active lease past its original expiry" do
    installation = create_installation!
    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation)
    started_at = Time.zone.parse("2026-04-01 00:00:00 UTC")

    first_decision = ProviderExecution::ProviderRequestGovernor.acquire(
      installation: installation,
      provider_handle: "local",
      effective_catalog: effective_catalog,
      now: started_at,
      lease_ttl_seconds: 10
    )

    ProviderExecution::ProviderRequestGovernor.renew(
      installation: installation,
      provider_handle: "local",
      effective_catalog: effective_catalog,
      lease_token: first_decision.lease_token,
      now: started_at + 9.seconds,
      lease_ttl_seconds: 10
    )

    blocked_decision = ProviderExecution::ProviderRequestGovernor.acquire(
      installation: installation,
      provider_handle: "local",
      effective_catalog: effective_catalog,
      now: started_at + 11.seconds,
      lease_ttl_seconds: 10
    )

    assert first_decision.allowed?
    assert blocked_decision.blocked?
    assert_equal "max_concurrent_requests", blocked_decision.reason
  ensure
    ProviderExecution::ProviderRequestGovernor.release(
      installation: installation,
      provider_handle: "local",
      effective_catalog: effective_catalog,
      lease_token: first_decision&.lease_token,
      now: started_at + 11.seconds
    )
  end

  test "persists a durable lease record for an admitted request" do
    installation = create_installation!
    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation)

    decision = ProviderExecution::ProviderRequestGovernor.acquire(
      installation: installation,
      provider_handle: "dev",
      effective_catalog: effective_catalog
    )

    lease = ProviderRequestLease.find_by!(lease_token: decision.lease_token)

    assert_equal installation, lease.installation
    assert_equal "dev", lease.provider_handle
    assert_nil lease.released_at
  ensure
    ProviderExecution::ProviderRequestGovernor.release(
      installation: installation,
      provider_handle: "dev",
      effective_catalog: effective_catalog,
      lease_token: decision&.lease_token
    )
  end
end
