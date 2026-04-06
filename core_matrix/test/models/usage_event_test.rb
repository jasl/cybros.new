require "test_helper"

class UsageEventTest < ActiveSupport::TestCase
  test "is explicitly classified as bounded audit data" do
    assert_equal :bounded_audit, UsageEvent.data_lifecycle_kind
  end

  test "captures usage dimensions for token-based events" do
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

    event = UsageEvent.create!(
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

  test "allows available prompt cache metrics with zero cached tokens" do
    event = UsageEvent.create!(
      installation: create_installation!,
      provider_handle: "openai",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: 100,
      output_tokens: 10,
      prompt_cache_status: "available",
      cached_input_tokens: 0,
      success: true,
      occurred_at: Time.utc(2026, 4, 6, 9, 0, 0)
    )

    assert_equal "available", event.prompt_cache_status
    assert_equal 0, event.cached_input_tokens
  end

  test "allows available prompt cache metrics with cached input tokens" do
    event = UsageEvent.create!(
      installation: create_installation!,
      provider_handle: "openai",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: 100,
      output_tokens: 10,
      prompt_cache_status: "available",
      cached_input_tokens: 12,
      success: true,
      occurred_at: Time.utc(2026, 4, 6, 9, 5, 0)
    )

    assert_equal "available", event.prompt_cache_status
    assert_equal 12, event.cached_input_tokens
  end

  test "rejects negative cached input tokens" do
    event = UsageEvent.new(
      installation: create_installation!,
      provider_handle: "openai",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      prompt_cache_status: "available",
      cached_input_tokens: -1,
      success: true,
      occurred_at: Time.utc(2026, 4, 6, 9, 10, 0)
    )

    assert_not event.valid?
    assert_includes event.errors[:cached_input_tokens], "must be greater than or equal to 0"
  end

  test "requires cached input tokens when prompt cache status is available" do
    event = UsageEvent.new(
      installation: create_installation!,
      provider_handle: "openai",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      prompt_cache_status: "available",
      cached_input_tokens: nil,
      success: true,
      occurred_at: Time.utc(2026, 4, 6, 9, 12, 0)
    )

    assert_not event.valid?
    assert_includes event.errors[:cached_input_tokens], "must be present when prompt cache status is available"
  end

  test "rejects cached input tokens when prompt cache status is unknown" do
    event = UsageEvent.new(
      installation: create_installation!,
      provider_handle: "openai",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      prompt_cache_status: "unknown",
      cached_input_tokens: 4,
      success: true,
      occurred_at: Time.utc(2026, 4, 6, 9, 15, 0)
    )

    assert_not event.valid?
    assert_includes event.errors[:cached_input_tokens], "must be blank unless prompt cache status is available"
  end

  test "rejects cached input tokens when prompt cache status is unsupported" do
    event = UsageEvent.new(
      installation: create_installation!,
      provider_handle: "openai",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      prompt_cache_status: "unsupported",
      cached_input_tokens: 4,
      success: true,
      occurred_at: Time.utc(2026, 4, 6, 9, 20, 0)
    )

    assert_not event.valid?
    assert_includes event.errors[:cached_input_tokens], "must be blank unless prompt cache status is available"
  end
end
