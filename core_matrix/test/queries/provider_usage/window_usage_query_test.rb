require "test_helper"

class ProviderUsage::WindowUsageQueryTest < ActiveSupport::TestCase
  test "aggregates rolling-window usage across dimension rollups for the same provider model and operation" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent_installation = create_agent_installation!(installation: installation)
    first_binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent_installation: agent_installation
    )
    second_binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent_installation: create_agent_installation!(installation: installation)
    )
    first_workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: first_binding,
      name: "First Workspace"
    )
    second_workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: second_binding,
      name: "Second Workspace"
    )
    window_key = "codex:2026-03-24T10"

    ProviderUsage::RecordEvent.call(
      installation: installation,
      user: user,
      workspace: first_workspace,
      provider_handle: "codex_subscription",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: 100,
      output_tokens: 40,
      latency_ms: 1200,
      estimated_cost: 0.0100,
      success: true,
      entitlement_window_key: window_key,
      occurred_at: Time.utc(2026, 3, 24, 10, 5, 0)
    )
    ProviderUsage::RecordEvent.call(
      installation: installation,
      user: user,
      workspace: second_workspace,
      provider_handle: "codex_subscription",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: 60,
      output_tokens: 20,
      latency_ms: 800,
      estimated_cost: 0.0200,
      success: false,
      entitlement_window_key: window_key,
      occurred_at: Time.utc(2026, 3, 24, 10, 15, 0)
    )
    ProviderUsage::RecordEvent.call(
      installation: installation,
      user: user,
      workspace: first_workspace,
      provider_handle: "codex_subscription",
      model_ref: "gpt-5.4-mini",
      operation_kind: "text_generation",
      input_tokens: 30,
      output_tokens: 10,
      latency_ms: 300,
      estimated_cost: 0.0030,
      success: true,
      entitlement_window_key: window_key,
      occurred_at: Time.utc(2026, 3, 24, 10, 25, 0)
    )
    ProviderUsage::RecordEvent.call(
      installation: installation,
      user: user,
      workspace: first_workspace,
      provider_handle: "codex_subscription",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: 20,
      output_tokens: 5,
      latency_ms: 250,
      estimated_cost: 0.0010,
      success: true,
      entitlement_window_key: "codex:2026-03-24T11",
      occurred_at: Time.utc(2026, 3, 24, 11, 5, 0)
    )

    result = ProviderUsage::WindowUsageQuery.call(
      installation: installation,
      window_key: window_key
    )

    primary_summary = result.find do |entry|
      entry.provider_handle == "codex_subscription" &&
        entry.model_ref == "gpt-5.4" &&
        entry.operation_kind == "text_generation"
    end
    secondary_summary = result.find do |entry|
      entry.provider_handle == "codex_subscription" &&
        entry.model_ref == "gpt-5.4-mini"
    end

    assert_equal window_key, primary_summary.window_key
    assert_equal 2, primary_summary.event_count
    assert_equal 1, primary_summary.success_count
    assert_equal 1, primary_summary.failure_count
    assert_equal 160, primary_summary.input_tokens_total
    assert_equal 60, primary_summary.output_tokens_total
    assert_equal 2000, primary_summary.total_latency_ms
    assert_equal BigDecimal("0.03"), primary_summary.estimated_cost_total

    assert_equal 1, secondary_summary.event_count
    assert_equal window_key, secondary_summary.window_key
    assert_equal 30, secondary_summary.input_tokens_total
    assert_equal 10, secondary_summary.output_tokens_total
  end

  test "returns an empty result when no rollups match the requested window" do
    installation = create_installation!

    result = ProviderUsage::WindowUsageQuery.call(
      installation: installation,
      window_key: "codex:2026-03-24T10"
    )

    assert_equal [], result
  end
end
