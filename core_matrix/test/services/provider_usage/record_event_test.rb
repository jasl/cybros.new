require "test_helper"

class ProviderUsage::RecordEventTest < ActiveSupport::TestCase
  test "records a usage event and projects hourly daily and rolling-window rollups" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent_program = create_agent_program!(installation: installation)
    execution_runtime = create_execution_runtime!(installation: installation)
    agent_program_version = create_agent_program_version!(
      installation: installation,
      agent_program: agent_program,
      execution_runtime: execution_runtime
    )
    binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: agent_program
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: binding
    )

    event = ProviderUsage::RecordEvent.call(
      installation: installation,
      user: user,
      workspace: workspace,
      conversation_id: 101,
      turn_id: 202,
      workflow_node_key: "planner-step",
      agent_program: agent_program,
      agent_program_version: agent_program_version,
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

    assert_equal 1, UsageEvent.count
    assert_equal event, UsageEvent.last
    assert_equal 3, UsageRollup.count
  end
end
