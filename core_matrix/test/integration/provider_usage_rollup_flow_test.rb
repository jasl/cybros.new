require "test_helper"

class ProviderUsageRollupFlowTest < ActionDispatch::IntegrationTest
  test "recording provider usage produces rollups keyed by hour day and explicit rolling-window identifiers" do
    installation = create_installation!

    ProviderUsage::RecordEvent.call(
      installation: installation,
      provider_handle: "codex_subscription",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: 100,
      output_tokens: 40,
      latency_ms: 1200,
      estimated_cost: 0.0100,
      success: true,
      entitlement_window_key: "codex:2026-03-24T10",
      occurred_at: Time.utc(2026, 3, 24, 10, 5, 0)
    )

    assert_equal ["2026-03-24", "2026-03-24T10", "codex:2026-03-24T10"], UsageRollup.order(:bucket_kind, :bucket_key).pluck(:bucket_key).sort
  end
end
