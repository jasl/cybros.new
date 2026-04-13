require "test_helper"

class ProviderUsage::RecordEventTest < ActiveSupport::TestCase
  test "records a usage event and projects hourly daily and rolling-window rollups" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)
    agent_definition_version = create_agent_definition_version!(
      installation: installation,
      agent: agent
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: agent
    )

    event = ProviderUsage::RecordEvent.call(
      installation: installation,
      user: user,
      workspace: workspace,
      conversation_id: 101,
      turn_id: 202,
      workflow_node_key: "planner-step",
      agent: agent,
      agent_definition_version: agent_definition_version,
      provider_handle: "openai",
      model_ref: "gpt-5.3-chat-latest",
      operation_kind: "text_generation",
      input_tokens: 120,
      output_tokens: 48,
      prompt_cache_status: "available",
      cached_input_tokens: 30,
      latency_ms: 3200,
      estimated_cost: 0.0125,
      success: true,
      entitlement_window_key: "codex:2026-03-24T10",
      occurred_at: Time.utc(2026, 3, 24, 10, 15, 0)
    )

    assert_equal 1, UsageEvent.count
    assert_equal event, UsageEvent.last
    assert_equal "available", event.prompt_cache_status
    assert_equal 30, event.cached_input_tokens
    assert_equal 3, UsageRollup.count
    assert_equal 30, UsageRollup.find_by!(bucket_kind: "hour", bucket_key: "2026-03-24T10").cached_input_tokens_total
  end
end
