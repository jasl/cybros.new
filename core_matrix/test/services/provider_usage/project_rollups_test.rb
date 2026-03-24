require "test_helper"

class ProviderUsage::ProjectRollupsTest < ActiveSupport::TestCase
  test "projects hourly daily and rolling-window rollups and accumulates repeated usage" do
    installation = create_installation!
    event = UsageEvent.create!(
      installation: installation,
      provider_handle: "openai",
      model_ref: "gpt-5.3-chat-latest",
      operation_kind: "text_generation",
      input_tokens: 120,
      output_tokens: 48,
      latency_ms: 3200,
      estimated_cost: 0.0125,
      success: true,
      entitlement_window_key: "codex:2026-03-24T10",
      occurred_at: Time.utc(2026, 3, 24, 10, 15, 0)
    )

    ProviderUsage::ProjectRollups.call(event: event)
    ProviderUsage::ProjectRollups.call(event: event)

    hourly = UsageRollup.find_by!(bucket_kind: "hour", bucket_key: "2026-03-24T10")
    daily = UsageRollup.find_by!(bucket_kind: "day", bucket_key: "2026-03-24")
    rolling = UsageRollup.find_by!(bucket_kind: "rolling_window", bucket_key: "codex:2026-03-24T10")

    assert_equal 2, hourly.event_count
    assert_equal 240, hourly.input_tokens_total
    assert_equal 96, hourly.output_tokens_total
    assert_equal 2, daily.event_count
    assert_equal 2, rolling.event_count
  end
end
