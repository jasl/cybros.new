require "test_helper"

class ProviderUsage::WindowUsageQueryTest < ActiveSupport::TestCase
  test "reads rollup-backed usage without raw usage events in scope" do
    installation = create_installation!
    window_key = "codex:2026-03-24T10"

    UsageRollup.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      bucket_kind: "rolling_window",
      bucket_key: window_key,
      dimension_digest: UsageRollup.dimension_digest_for(
        user_id: nil,
        workspace_id: nil,
        conversation_id: nil,
        turn_id: nil,
        workflow_node_key: nil,
        agent_program_id: nil,
        agent_program_version_id: nil,
        provider_handle: "codex_subscription",
        model_ref: "gpt-5.4",
        operation_kind: "text_generation"
      ),
      event_count: 2,
      success_count: 1,
      failure_count: 1,
      input_tokens_total: 160,
      output_tokens_total: 60,
      cached_input_tokens_total: 40,
      prompt_cache_available_event_count: 1,
      prompt_cache_unknown_event_count: 1,
      prompt_cache_unsupported_event_count: 0,
      media_units_total: 0,
      total_latency_ms: 2000,
      estimated_cost_total: 0.03
    )
    UsageRollup.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      model_ref: "gpt-5.4-mini",
      operation_kind: "text_generation",
      bucket_kind: "rolling_window",
      bucket_key: window_key,
      dimension_digest: UsageRollup.dimension_digest_for(
        user_id: nil,
        workspace_id: nil,
        conversation_id: nil,
        turn_id: nil,
        workflow_node_key: nil,
        agent_program_id: nil,
        agent_program_version_id: nil,
        provider_handle: "codex_subscription",
        model_ref: "gpt-5.4-mini",
        operation_kind: "text_generation"
      ),
      event_count: 1,
      success_count: 1,
      failure_count: 0,
      input_tokens_total: 30,
      output_tokens_total: 10,
      cached_input_tokens_total: 0,
      prompt_cache_available_event_count: 0,
      prompt_cache_unknown_event_count: 0,
      prompt_cache_unsupported_event_count: 1,
      media_units_total: 0,
      total_latency_ms: 300,
      estimated_cost_total: 0.003
    )

    result = ProviderUsage::WindowUsageQuery.call(
      installation: installation,
      window_key: window_key
    )

    assert_equal 2, result.length
    primary_summary = result.find do |entry|
      entry.provider_handle == "codex_subscription" &&
        entry.model_ref == "gpt-5.4"
    end
    secondary_summary = result.find do |entry|
      entry.provider_handle == "codex_subscription" &&
        entry.model_ref == "gpt-5.4-mini"
    end

    assert_equal 2, primary_summary.event_count
    assert_equal 1, primary_summary.success_count
    assert_equal 1, primary_summary.failure_count
    assert_equal 160, primary_summary.input_tokens_total
    assert_equal 60, primary_summary.output_tokens_total
    assert_equal 40, primary_summary.cached_input_tokens_total
    assert_equal 1, primary_summary.prompt_cache_available_event_count
    assert_equal 1, primary_summary.prompt_cache_unknown_event_count
    assert_equal 0, primary_summary.prompt_cache_unsupported_event_count
    assert_equal 2000, primary_summary.total_latency_ms
    assert_equal BigDecimal("0.03"), primary_summary.estimated_cost_total

    assert_equal 1, secondary_summary.event_count
    assert_equal 30, secondary_summary.input_tokens_total
    assert_equal 10, secondary_summary.output_tokens_total
    assert_equal 1, secondary_summary.prompt_cache_unsupported_event_count
  end

  test "aggregates rolling-window usage across dimension rollups for the same provider model and operation" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent_program = create_agent_program!(installation: installation)
    first_binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: agent_program
    )
    second_binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: create_agent_program!(installation: installation)
    )
    first_workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: first_binding,
      name: "First Workspace"
    )
    second_workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: second_binding,
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
      prompt_cache_status: "available",
      cached_input_tokens: 50,
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
      prompt_cache_status: "unknown",
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
      prompt_cache_status: "unsupported",
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
    assert_equal 50, primary_summary.cached_input_tokens_total
    assert_equal 1, primary_summary.prompt_cache_available_event_count
    assert_equal 1, primary_summary.prompt_cache_unknown_event_count
    assert_equal 0, primary_summary.prompt_cache_unsupported_event_count
    assert_equal 2000, primary_summary.total_latency_ms
    assert_equal BigDecimal("0.03"), primary_summary.estimated_cost_total

    assert_equal 1, secondary_summary.event_count
    assert_equal window_key, secondary_summary.window_key
    assert_equal 30, secondary_summary.input_tokens_total
    assert_equal 10, secondary_summary.output_tokens_total
    assert_equal 1, secondary_summary.prompt_cache_unsupported_event_count
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
