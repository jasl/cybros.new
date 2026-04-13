require "test_helper"

class ConversationDiagnostics::RecomputeTurnSnapshotTest < ActiveSupport::TestCase
  test "recomputes one turn snapshot from durable usage and runtime facts" do
    context = build_agent_control_context!
    turn = context[:turn]
    workflow_run = context[:workflow_run]
    workflow_node = context[:workflow_node]

    Turns::SteerCurrentInput.call(turn: turn, content: "Revised input")
    attach_selected_output!(turn, content: "First output", variant_index: 0)
    attach_selected_output!(turn, content: "Second output", variant_index: 1)

    create_tool_execution!(
      context: context,
      workflow_node: workflow_node,
      tool_status: "succeeded",
      command_line: "cd /workspace/app && npm test",
      command_state: "completed"
    )
    create_tool_execution!(
      context: context,
      workflow_node: workflow_node,
      tool_status: "failed",
      command_line: "cd /workspace/app && npm run build",
      command_state: "failed"
    )

    create_process_run!(
      workflow_node: workflow_node,
      execution_runtime: context[:execution_runtime],
      conversation: context[:conversation],
      turn: turn,
      lifecycle_state: "lost",
      started_at: 2.minutes.ago,
      ended_at: 1.minute.ago
    )

    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: context[:conversation],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      kind: "fork",
      addressability: "agent_addressable"
    )
    SubagentConnection.create!(
      installation: context[:installation],
      user: context[:user],
      workspace: context[:workspace],
      agent: context[:agent],
      owner_conversation: context[:conversation],
      conversation: child_conversation,
      origin_turn: turn,
      scope: "turn",
      profile_key: "researcher",
      depth: 0,
      observed_status: "completed"
    )

    running_task = create_agent_task_run!(
      workflow_node: workflow_node,
      lifecycle_state: "completed",
      started_at: 3.minutes.ago,
      finished_at: 2.minutes.ago,
      logical_work_id: "resumeable-work",
      task_payload: { "delivery_kind" => "turn_resume" }
    )
    create_agent_task_run!(
      workflow_node: workflow_node,
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      logical_work_id: "retryable-work",
      task_payload: { "delivery_kind" => "step_retry" }
    )
    create_agent_task_run!(
      workflow_node: workflow_node,
      lifecycle_state: "completed",
      started_at: 1.minute.ago,
      finished_at: 30.seconds.ago,
      logical_work_id: "paused-retry-work",
      task_payload: { "delivery_kind" => "paused_retry" }
    )

    workflow_run.update!(
      wait_state: "waiting",
      wait_reason_kind: "manual_recovery_required",
      waiting_since_at: Time.current,
      wait_reason_payload: {},
      recovery_state: "paused_turn",
      recovery_agent_task_run_public_id: running_task.public_id
    )

    record_usage_event!(
      context: context,
      workflow_node: workflow_node,
      input_tokens: 120,
      output_tokens: 40,
      prompt_cache_status: "available",
      cached_input_tokens: 60,
      latency_ms: 1_300,
      estimated_cost: 0.010,
      success: true,
      occurred_at: Time.utc(2026, 4, 2, 10, 0, 0)
    )
    record_usage_event!(
      context: context,
      workflow_node: workflow_node,
      input_tokens: 30,
      output_tokens: 10,
      prompt_cache_status: "unknown",
      latency_ms: 500,
      estimated_cost: 0.002,
      success: false,
      user: nil,
      occurred_at: Time.utc(2026, 4, 2, 10, 5, 0)
    )

    snapshot = ConversationDiagnostics::RecomputeTurnSnapshot.call(turn: turn)

    assert_equal turn, snapshot.turn
    assert_equal context[:conversation], snapshot.conversation
    assert_equal "active", snapshot.lifecycle_state
    assert_equal 2, snapshot.usage_event_count
    assert_equal 150, snapshot.input_tokens_total
    assert_equal 50, snapshot.output_tokens_total
    assert_equal BigDecimal("0.012"), snapshot.estimated_cost_total
    assert_equal 60, snapshot.cached_input_tokens_total
    assert_equal 1, snapshot.prompt_cache_available_event_count
    assert_equal 1, snapshot.prompt_cache_unknown_event_count
    assert_equal 0, snapshot.prompt_cache_unsupported_event_count
    assert_equal 1, snapshot.attributed_user_usage_event_count
    assert_equal 120, snapshot.attributed_user_input_tokens_total
    assert_equal 40, snapshot.attributed_user_output_tokens_total
    assert_equal BigDecimal("0.01"), snapshot.attributed_user_estimated_cost_total
    assert_equal 2, snapshot.provider_round_count
    assert_equal 2, snapshot.tool_call_count
    assert_equal 1, snapshot.tool_failure_count
    assert_equal 2, snapshot.command_run_count
    assert_equal 1, snapshot.command_failure_count
    assert_equal 1, snapshot.process_run_count
    assert_equal 1, snapshot.process_failure_count
    assert_equal 1, snapshot.subagent_connection_count
    assert_equal 2, snapshot.input_variant_count
    assert_equal 2, snapshot.output_variant_count
    assert_equal 1, snapshot.resume_attempt_count
    assert_equal 2, snapshot.retry_attempt_count
    assert_equal 900, snapshot.avg_latency_ms
    assert_equal 1300, snapshot.max_latency_ms
    assert_equal 2, snapshot.estimated_cost_event_count
    assert_equal 0, snapshot.estimated_cost_missing_event_count
    assert_equal 1, snapshot.attributed_user_estimated_cost_event_count
    assert_equal 0, snapshot.attributed_user_estimated_cost_missing_event_count
    assert_equal "paused_turn", snapshot.pause_state

    provider_breakdown = snapshot.metadata.fetch("provider_usage_breakdown")
    assert_equal 1, provider_breakdown.length
    assert_equal "openrouter", provider_breakdown.first.fetch("provider_handle")
    assert_equal "openai-gpt-5.4", provider_breakdown.first.fetch("model_ref")
    assert_equal 2, provider_breakdown.first.fetch("event_count")
    assert_equal 2, provider_breakdown.first.fetch("estimated_cost_event_count")
    assert_equal 0, provider_breakdown.first.fetch("estimated_cost_missing_event_count")
    assert_equal 2, provider_breakdown.first.fetch("latency_event_count")
    assert_equal 900, provider_breakdown.first.fetch("avg_latency_ms")
    assert_equal 1300, provider_breakdown.first.fetch("max_latency_ms")
    assert_equal 60, provider_breakdown.first.fetch("cached_input_tokens_total")
    assert_equal 1, provider_breakdown.first.fetch("prompt_cache_available_event_count")
    assert_equal 1, provider_breakdown.first.fetch("prompt_cache_unknown_event_count")
    assert_equal 0, provider_breakdown.first.fetch("prompt_cache_unsupported_event_count")
    assert_equal 0.5, provider_breakdown.first.fetch("prompt_cache_hit_rate")

    attributed_provider_breakdown = snapshot.metadata.fetch("attributed_user_provider_usage_breakdown")
    assert_equal 1, attributed_provider_breakdown.length
    assert_equal 1, attributed_provider_breakdown.first.fetch("event_count")
    assert_equal 120, attributed_provider_breakdown.first.fetch("input_tokens_total")
    assert_equal 40, attributed_provider_breakdown.first.fetch("output_tokens_total")
    assert_equal "0.01", attributed_provider_breakdown.first.fetch("estimated_cost_total")
    assert_equal 1, attributed_provider_breakdown.first.fetch("estimated_cost_event_count")
    assert_equal 0, attributed_provider_breakdown.first.fetch("estimated_cost_missing_event_count")
    assert_equal 60, attributed_provider_breakdown.first.fetch("cached_input_tokens_total")
    assert_equal 1, attributed_provider_breakdown.first.fetch("prompt_cache_available_event_count")
    assert_equal 0.5, attributed_provider_breakdown.first.fetch("prompt_cache_hit_rate")

    assert_equal({ "turn_step" => 1, "turn_root" => 1 }, snapshot.metadata.fetch("workflow_node_type_counts"))
    assert_equal({ "exec_command" => { "count" => 2, "failures" => 1 } }, snapshot.metadata.fetch("tool_breakdown"))
    assert_equal(
      { "completed" => 1, "failed" => 1 },
      snapshot.metadata.fetch("command_lifecycle_state_counts")
    )
    assert_equal({ "completed" => 1 }, snapshot.metadata.fetch("subagent_status_counts"))
    assert_equal(
      900,
      snapshot.avg_latency_ms
    )
    assert_nil snapshot.metadata["evidence_refs"]

    TurnDiagnosticsSnapshot.where(turn: turn).delete_all
    recreated_snapshot = ConversationDiagnostics::RecomputeTurnSnapshot.call(turn: turn)

    assert_equal snapshot.turn_id, recreated_snapshot.turn_id
    assert_equal snapshot.usage_event_count, recreated_snapshot.usage_event_count
    assert_equal 1, TurnDiagnosticsSnapshot.where(turn: turn).count
  end

  test "marks cost data unavailable when usage events have no estimated cost" do
    context = build_agent_control_context!
    turn = context[:turn]
    workflow_node = context[:workflow_node]

    record_usage_event!(
      context: context,
      workflow_node: workflow_node,
      input_tokens: 50,
      output_tokens: 25,
      prompt_cache_status: "unsupported",
      latency_ms: 800,
      estimated_cost: nil,
      success: true,
      occurred_at: Time.utc(2026, 4, 2, 11, 0, 0)
    )

    snapshot = ConversationDiagnostics::RecomputeTurnSnapshot.call(turn: turn)

    assert_equal BigDecimal("0"), snapshot.estimated_cost_total
    assert_equal 0, snapshot.estimated_cost_event_count
    assert_equal 1, snapshot.estimated_cost_missing_event_count
    assert_equal 0, snapshot.metadata.fetch("provider_usage_breakdown").first.fetch("estimated_cost_event_count")
    assert_equal 1, snapshot.metadata.fetch("provider_usage_breakdown").first.fetch("estimated_cost_missing_event_count")
    assert_nil snapshot.metadata.fetch("provider_usage_breakdown").first["prompt_cache_hit_rate"]
  end

  test "recomputes one turn snapshot within sixteen SQL queries" do
    context = build_agent_control_context!
    turn = context[:turn]
    workflow_node = context[:workflow_node]

    create_tool_execution!(
      context: context,
      workflow_node: workflow_node,
      tool_status: "failed",
      command_line: "bin/test",
      command_state: "failed"
    )
    create_process_run!(
      workflow_node: workflow_node,
      execution_runtime: context[:execution_runtime],
      conversation: context[:conversation],
      turn: turn,
      lifecycle_state: "lost",
      started_at: 2.minutes.ago,
      ended_at: 1.minute.ago
    )
    create_agent_task_run!(
      workflow_node: workflow_node,
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      logical_work_id: "retryable-work",
      task_payload: { "delivery_kind" => "step_retry" }
    )
    record_usage_event!(
      context: context,
      workflow_node: workflow_node,
      input_tokens: 40,
      output_tokens: 10,
      prompt_cache_status: "available",
      cached_input_tokens: 20,
      latency_ms: 500,
      estimated_cost: 0.004,
      success: true,
      occurred_at: Time.utc(2026, 4, 2, 12, 0, 0)
    )

    assert_sql_query_count_at_most(16) do
      ConversationDiagnostics::RecomputeTurnSnapshot.call(turn: turn)
    end
  end

  private

  def create_tool_execution!(context:, workflow_node:, tool_status:, command_line:, command_state:)
    capability_snapshot = context[:agent_definition_version]

    tool_definition = ToolDefinition.find_or_create_by!(
      installation: context[:installation],
      agent_definition_version: capability_snapshot,
      tool_name: "exec_command"
    ) do |definition|
      definition.tool_kind = "function"
      definition.governance_mode = "reserved"
      definition.policy_payload = {}
    end
    implementation_source = ImplementationSource.find_or_create_by!(
      installation: context[:installation],
      source_kind: "kernel",
      source_ref: "core_matrix.exec_command.shared"
    ) do |source|
      source.metadata = {}
    end
    tool_implementation = ToolImplementation.find_or_create_by!(
      installation: context[:installation],
      tool_definition: tool_definition,
      implementation_ref: "core_matrix.exec_command.shared"
    ) do |implementation|
      implementation.implementation_source = implementation_source
      implementation.idempotency_policy = "idempotent"
      implementation.default_for_snapshot = true
      implementation.input_schema = {}
      implementation.result_schema = {}
      implementation.metadata = {}
    end
    tool_binding = ToolBinding.find_or_create_by!(
      installation: context[:installation],
      workflow_node: workflow_node,
      tool_definition: tool_definition
    ) do |binding|
      binding.tool_implementation = tool_implementation
      binding.binding_reason = "snapshot_default"
      binding.runtime_state = {}
    end
    tool_invocation = ToolInvocation.create!(
      installation: context[:installation],
      user: context[:user],
      workspace: context[:workspace],
      agent: context[:agent],
      conversation: context[:conversation],
      turn: context[:turn],
      workflow_run: workflow_node.workflow_run,
      workflow_node: workflow_node,
      tool_binding: tool_binding,
      tool_definition: tool_definition,
      tool_implementation: tool_implementation,
      attempt_no: tool_binding.tool_invocations.count + 1,
      status: tool_status,
      request_payload: {},
      response_payload: {},
      error_payload: {},
      metadata: {},
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )

    CommandRun.create!(
      installation: context[:installation],
      user: context[:user],
      workspace: context[:workspace],
      agent: context[:agent],
      conversation: context[:conversation],
      turn: context[:turn],
      workflow_run: workflow_node.workflow_run,
      workflow_node: workflow_node,
      tool_invocation: tool_invocation,
      command_line: command_line,
      lifecycle_state: command_state,
      metadata: {},
      started_at: 2.minutes.ago,
      ended_at: 1.minute.ago,
      exit_status: (command_state == "completed" ? 0 : 1)
    )
  end

  def record_usage_event!(context:, workflow_node:, input_tokens:, output_tokens:, latency_ms:, estimated_cost:, success:, occurred_at:, user: context[:user], prompt_cache_status: nil, cached_input_tokens: nil)
    ProviderUsage::RecordEvent.call(
      installation: context[:installation],
      user: user,
      workspace: context[:workspace],
      conversation_id: context[:conversation].id,
      turn_id: context[:turn].id,
      workflow_node_key: workflow_node.node_key,
      agent: context[:agent],
      agent_definition_version: context[:agent_definition_version],
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      prompt_cache_status: prompt_cache_status,
      cached_input_tokens: cached_input_tokens,
      latency_ms: latency_ms,
      estimated_cost: estimated_cost,
      success: success,
      occurred_at: occurred_at
    )
  end
end
