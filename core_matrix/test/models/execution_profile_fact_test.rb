require "test_helper"

class ExecutionProfileFactTest < ActiveSupport::TestCase
  test "supports generic execution fact kinds and runtime references" do
    installation = create_installation!
    user = create_user!(installation: installation)
    binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent: create_agent!(installation: installation)
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: binding
    )

    tool_call = ExecutionProfileFact.create!(
      installation: installation,
      user: user,
      workspace: workspace,
      conversation_id: 101,
      turn_id: 202,
      workflow_node_key: "tool-step",
      fact_kind: "tool_call",
      fact_key: "exec_command",
      count_value: 1,
      success: true,
      occurred_at: Time.utc(2026, 3, 24, 12, 0, 0),
      metadata: {}
    )
    provider_request = ExecutionProfileFact.create!(
      installation: installation,
      user: user,
      workspace: workspace,
      conversation_id: 101,
      turn_id: 202,
      workflow_node_key: "turn-step",
      fact_kind: "provider_request",
      fact_key: "turn_step",
      duration_ms: 1_250,
      success: true,
      occurred_at: Time.utc(2026, 3, 24, 12, 2, 0),
      provider_request_id: "req-123",
      provider_handle: "openrouter",
      model_ref: "openai/gpt-5.4",
      api_model: "gpt-5.4",
      wire_api: "responses",
      total_tokens: 22,
      recommended_compaction_threshold: 50,
      threshold_crossed: false,
      metadata: {}
    )
    subagent_outcome = ExecutionProfileFact.create!(
      installation: installation,
      fact_kind: "subagent_outcome",
      fact_key: "planner",
      subagent_connection_id: 303,
      success: false,
      occurred_at: Time.utc(2026, 3, 24, 12, 5, 0),
      metadata: { "reason" => "timeout" }
    )
    approval_wait = ExecutionProfileFact.create!(
      installation: installation,
      fact_kind: "approval_wait",
      fact_key: "human_gate",
      human_interaction_request_id: 404,
      duration_ms: 45_000,
      occurred_at: Time.utc(2026, 3, 24, 12, 10, 0),
      metadata: {}
    )
    process_failure = ExecutionProfileFact.create!(
      installation: installation,
      fact_kind: "process_failure",
      fact_key: "sandbox_exec",
      process_run_id: 505,
      success: false,
      occurred_at: Time.utc(2026, 3, 24, 12, 15, 0),
      metadata: { "exit_code" => 1 }
    )

    assert tool_call.tool_call?
    assert provider_request.provider_request?
    assert subagent_outcome.subagent_outcome?
    assert approval_wait.approval_wait?
    assert process_failure.process_failure?
    assert_equal 45_000, approval_wait.duration_ms
    assert_equal 505, process_failure.process_run_id
    assert_equal "req-123", provider_request.provider_request_id
    assert_equal "openrouter", provider_request.provider_handle
    assert_equal "openai/gpt-5.4", provider_request.model_ref
    assert_equal "gpt-5.4", provider_request.api_model
    assert_equal "responses", provider_request.wire_api
    assert_equal 22, provider_request.total_tokens
    assert_equal 50, provider_request.recommended_compaction_threshold
    assert_equal false, provider_request.threshold_crossed
  end

  test "rejects cross installation references" do
    installation = create_installation!
    other_installation = Installation.new(
      name: "Other Matrix",
      bootstrap_state: "bootstrapped",
      global_settings: {}
    )
    other_installation.save!(validate: false)

    fact = ExecutionProfileFact.new(
      installation: installation,
      user: create_user!(installation: other_installation),
      workspace: create_workspace!(installation: other_installation),
      fact_kind: "tool_call",
      fact_key: "exec_command",
      occurred_at: Time.utc(2026, 3, 24, 12, 0, 0),
      metadata: {}
    )

    assert_not fact.valid?
    assert_includes fact.errors[:user], "must belong to the same installation"
    assert_includes fact.errors[:workspace], "must belong to the same installation"
  end

  test "rejects non hash metadata" do
    fact = ExecutionProfileFact.new(
      installation: create_installation!,
      fact_kind: "process_failure",
      fact_key: "sandbox_exec",
      occurred_at: Time.utc(2026, 3, 24, 12, 15, 0),
      metadata: "invalid"
    )

    assert_not fact.valid?
    assert_includes fact.errors[:metadata], "must be a hash"
  end

  test "rejects provider request metadata that duplicates structured fields" do
    fact = ExecutionProfileFact.new(
      installation: create_installation!,
      fact_kind: "provider_request",
      fact_key: "turn_step",
      occurred_at: Time.utc(2026, 3, 24, 12, 15, 0),
      provider_request_id: "req-123",
      provider_handle: "openrouter",
      model_ref: "openai/gpt-5.4",
      api_model: "gpt-5.4",
      wire_api: "responses",
      total_tokens: 20,
      threshold_crossed: false,
      metadata: { "provider_request_id" => "req-123", "usage_evaluation" => { "total_tokens" => 20 } }
    )

    assert_not fact.valid?
    assert_includes fact.errors[:metadata], "must not duplicate structured provider request fields"
  end
end
