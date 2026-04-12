require "test_helper"

class UsageRollupTest < ActiveSupport::TestCase
  test "is explicitly classified as a retained aggregate" do
    assert_equal :retained_aggregate, UsageRollup.data_lifecycle_kind
  end

  test "enforces uniqueness by bucket and dimensions" do
    installation = create_installation!
    dimension_digest = UsageRollup.dimension_digest_for(
      user_id: nil,
      workspace_id: nil,
      conversation_id: 101,
      turn_id: 202,
      workflow_node_key: "planner-step",
      agent_id: nil,
      agent_definition_version_id: nil,
      provider_handle: "openai",
      model_ref: "gpt-5.3-chat-latest",
      operation_kind: "text_generation"
    )

    UsageRollup.create!(
      installation: installation,
      conversation_id: 101,
      turn_id: 202,
      workflow_node_key: "planner-step",
      provider_handle: "openai",
      model_ref: "gpt-5.3-chat-latest",
      operation_kind: "text_generation",
      bucket_kind: "hour",
      bucket_key: "2026-03-24T10",
      dimension_digest: dimension_digest,
      event_count: 1,
      success_count: 1,
      failure_count: 0,
      input_tokens_total: 120,
      output_tokens_total: 48,
      media_units_total: 0,
      total_latency_ms: 3200,
      estimated_cost_total: 0.0125
    )

    duplicate = UsageRollup.new(
      installation: installation,
      conversation_id: 101,
      turn_id: 202,
      workflow_node_key: "planner-step",
      provider_handle: "openai",
      model_ref: "gpt-5.3-chat-latest",
      operation_kind: "text_generation",
      bucket_kind: "hour",
      bucket_key: "2026-03-24T10",
      dimension_digest: dimension_digest,
      event_count: 1,
      success_count: 1,
      failure_count: 0,
      input_tokens_total: 120,
      output_tokens_total: 48,
      media_units_total: 0,
      total_latency_ms: 3200,
      estimated_cost_total: 0.0125
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:dimension_digest], "has already been taken"
  end

  test "supports explicit rolling-window bucket identifiers" do
    rollup = UsageRollup.create!(
      installation: create_installation!,
      provider_handle: "codex_subscription",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      bucket_kind: "rolling_window",
      bucket_key: "codex:2026-03-24T10",
      dimension_digest: UsageRollup.dimension_digest_for(
        user_id: nil,
        workspace_id: nil,
        conversation_id: nil,
        turn_id: nil,
        workflow_node_key: nil,
        agent_id: nil,
        agent_definition_version_id: nil,
        provider_handle: "codex_subscription",
        model_ref: "gpt-5.4",
        operation_kind: "text_generation"
      ),
      event_count: 1,
      success_count: 1,
      failure_count: 0,
      input_tokens_total: 100,
      output_tokens_total: 50,
      media_units_total: 0,
      total_latency_ms: 1000,
      estimated_cost_total: 0.015
    )

    assert rollup.rolling_window?
    assert_equal "codex:2026-03-24T10", rollup.bucket_key
  end

  test "stores prompt cache aggregate counters" do
    rollup = UsageRollup.create!(
      installation: create_installation!,
      provider_handle: "openai",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      bucket_kind: "day",
      bucket_key: "2026-04-06",
      dimension_digest: UsageRollup.dimension_digest_for(
        user_id: nil,
        workspace_id: nil,
        conversation_id: nil,
        turn_id: nil,
        workflow_node_key: nil,
        agent_id: nil,
        agent_definition_version_id: nil,
        provider_handle: "openai",
        model_ref: "gpt-5.4",
        operation_kind: "text_generation"
      ),
      event_count: 2,
      success_count: 2,
      failure_count: 0,
      input_tokens_total: 240,
      output_tokens_total: 24,
      media_units_total: 0,
      total_latency_ms: 2000,
      estimated_cost_total: 0.020,
      cached_input_tokens_total: 60,
      prompt_cache_available_event_count: 1,
      prompt_cache_unknown_event_count: 1,
      prompt_cache_unsupported_event_count: 0
    )

    assert_equal 60, rollup.cached_input_tokens_total
    assert_equal 1, rollup.prompt_cache_available_event_count
    assert_equal 1, rollup.prompt_cache_unknown_event_count
    assert_equal 0, rollup.prompt_cache_unsupported_event_count
  end

  test "rejects negative prompt cache aggregate counters" do
    rollup = UsageRollup.new(
      installation: create_installation!,
      provider_handle: "openai",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      bucket_kind: "day",
      bucket_key: "2026-04-06",
      dimension_digest: UsageRollup.dimension_digest_for(
        user_id: nil,
        workspace_id: nil,
        conversation_id: nil,
        turn_id: nil,
        workflow_node_key: nil,
        agent_id: nil,
        agent_definition_version_id: nil,
        provider_handle: "openai",
        model_ref: "gpt-5.4",
        operation_kind: "text_generation"
      ),
      event_count: 1,
      success_count: 1,
      failure_count: 0,
      input_tokens_total: 120,
      output_tokens_total: 12,
      media_units_total: 0,
      total_latency_ms: 1000,
      estimated_cost_total: 0.010,
      cached_input_tokens_total: -1,
      prompt_cache_available_event_count: -1,
      prompt_cache_unknown_event_count: 0,
      prompt_cache_unsupported_event_count: 0
    )

    assert_not rollup.valid?
    assert_includes rollup.errors[:cached_input_tokens_total], "must be greater than or equal to 0"
    assert_includes rollup.errors[:prompt_cache_available_event_count], "must be greater than or equal to 0"
  end
end
