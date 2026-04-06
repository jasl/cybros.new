require "test_helper"

class ProviderUsage::ProjectRollupsTest < ActiveSupport::TestCase
  test "projects prompt cache counters and cached token totals by status" do
    installation = create_installation!
    available_event = UsageEvent.create!(
      installation: installation,
      provider_handle: "openai",
      model_ref: "gpt-5.3-chat-latest",
      operation_kind: "text_generation",
      input_tokens: 120,
      output_tokens: 48,
      prompt_cache_status: "available",
      cached_input_tokens: 7,
      latency_ms: 3200,
      estimated_cost: 0.0125,
      success: true,
      entitlement_window_key: "codex:2026-03-24T10",
      occurred_at: Time.utc(2026, 3, 24, 10, 15, 0)
    )
    zero_cache_event = UsageEvent.create!(
      installation: installation,
      provider_handle: "openai",
      model_ref: "gpt-5.3-chat-latest",
      operation_kind: "text_generation",
      input_tokens: 60,
      output_tokens: 20,
      prompt_cache_status: "available",
      cached_input_tokens: 0,
      latency_ms: 900,
      estimated_cost: 0.005,
      success: true,
      entitlement_window_key: "codex:2026-03-24T10",
      occurred_at: Time.utc(2026, 3, 24, 10, 20, 0)
    )
    unknown_event = UsageEvent.create!(
      installation: installation,
      provider_handle: "openai",
      model_ref: "gpt-5.3-chat-latest",
      operation_kind: "text_generation",
      input_tokens: 10,
      output_tokens: 5,
      prompt_cache_status: "unknown",
      latency_ms: 120,
      estimated_cost: 0.001,
      success: false,
      entitlement_window_key: "codex:2026-03-24T10",
      occurred_at: Time.utc(2026, 3, 24, 10, 25, 0)
    )
    unsupported_event = UsageEvent.create!(
      installation: installation,
      provider_handle: "openai",
      model_ref: "gpt-5.3-chat-latest",
      operation_kind: "text_generation",
      input_tokens: 5,
      output_tokens: 1,
      prompt_cache_status: "unsupported",
      latency_ms: 80,
      estimated_cost: 0.0005,
      success: true,
      entitlement_window_key: "codex:2026-03-24T10",
      occurred_at: Time.utc(2026, 3, 24, 10, 30, 0)
    )

    [available_event, zero_cache_event, unknown_event, unsupported_event].each do |event|
      ProviderUsage::ProjectRollups.call(event: event)
    end

    hourly = UsageRollup.find_by!(bucket_kind: "hour", bucket_key: "2026-03-24T10")
    daily = UsageRollup.find_by!(bucket_kind: "day", bucket_key: "2026-03-24")
    rolling = UsageRollup.find_by!(bucket_kind: "rolling_window", bucket_key: "codex:2026-03-24T10")

    assert_equal 4, hourly.event_count
    assert_equal 195, hourly.input_tokens_total
    assert_equal 74, hourly.output_tokens_total
    assert_equal 7, hourly.cached_input_tokens_total
    assert_equal 2, hourly.prompt_cache_available_event_count
    assert_equal 1, hourly.prompt_cache_unknown_event_count
    assert_equal 1, hourly.prompt_cache_unsupported_event_count
    assert_equal 4, daily.event_count
    assert_equal 4, rolling.event_count
  end
end
