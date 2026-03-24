require "test_helper"

class UsageEventTest < ActiveSupport::TestCase
  test "captures usage dimensions for token-based events" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent_installation = create_agent_installation!(installation: installation)
    execution_environment = create_execution_environment!(installation: installation)
    agent_deployment = create_agent_deployment!(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: execution_environment
    )
    binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent_installation: agent_installation
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: binding
    )

    event = UsageEvent.create!(
      installation: installation,
      user: user,
      workspace: workspace,
      conversation_id: 101,
      turn_id: 202,
      workflow_node_key: "planner-step",
      agent_installation: agent_installation,
      agent_deployment: agent_deployment,
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

    assert_equal user, event.user
    assert_equal workspace, event.workspace
    assert_equal 101, event.conversation_id
    assert_equal 202, event.turn_id
    assert_equal "planner-step", event.workflow_node_key
    assert_equal "openai", event.provider_handle
    assert_equal "gpt-5.3-chat-latest", event.model_ref
    assert event.text_generation?
    assert_equal 120, event.input_tokens
    assert_equal 48, event.output_tokens
    assert_equal BigDecimal("0.0125"), event.estimated_cost
  end

  test "supports media-unit usage without token counts" do
    event = UsageEvent.create!(
      installation: create_installation!,
      provider_handle: "openai",
      model_ref: "gpt-5.3-chat-latest",
      operation_kind: "transcription",
      media_units: 3,
      latency_ms: 1500,
      estimated_cost: 0.004,
      success: true,
      occurred_at: Time.utc(2026, 3, 24, 11, 5, 0)
    )

    assert event.transcription?
    assert_equal 3, event.media_units
    assert_nil event.input_tokens
    assert_nil event.output_tokens
  end
end
