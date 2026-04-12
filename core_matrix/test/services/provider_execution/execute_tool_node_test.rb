require "test_helper"

class ProviderExecution::ExecuteToolNodeTest < ActiveSupport::TestCase
  test "executes a tool_call workflow node and requeues its successor graph nodes" do
    context = build_governed_tool_context!
    root_node = context.fetch(:workflow_node)
    source_binding = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: root_node,
      tool_catalog: [calculator_tool_entry]
    ).includes(:tool_definition, :tool_implementation).sole

    Workflows::Mutate.call(
      workflow_run: root_node.workflow_run,
      nodes: [
        {
          node_key: "provider_round_1_tool_1",
          node_type: "tool_call",
          decision_source: "llm",
          yielding_node_key: root_node.node_key,
          metadata: {},
          tool_call_payload: {
            "call_id" => "call-calculator-1",
            "tool_name" => "calculator",
            "arguments" => { "expression" => "2 + 2" },
            "provider_format" => "chat_completions",
          },
        },
        {
          node_key: "provider_round_1_join_1",
          node_type: "barrier_join",
          decision_source: "system",
          metadata: {},
        },
      ],
      edges: [
        {
          from_node_key: root_node.node_key,
          to_node_key: "provider_round_1_tool_1",
        },
        {
          from_node_key: "provider_round_1_tool_1",
          to_node_key: "provider_round_1_join_1",
        },
      ]
    )

    tool_node = root_node.workflow_run.reload.workflow_nodes.find_by!(node_key: "provider_round_1_tool_1")
    join_node = root_node.workflow_run.workflow_nodes.find_by!(node_key: "provider_round_1_join_1")

    ToolBinding.create!(
      installation: tool_node.installation,
      workflow_node: tool_node,
      tool_definition: source_binding.tool_definition,
      tool_implementation: source_binding.tool_implementation,
      binding_reason: "snapshot_default",
      runtime_state: source_binding.runtime_state,
      round_scoped: source_binding.round_scoped,
      parallel_safe: source_binding.parallel_safe
    )

    result = ProviderExecution::ExecuteToolNode.call(
      workflow_node: tool_node,
      agent_request_exchange: ProviderExecutionTestSupport::FakeAgentRequestExchange.new(
        tool_results: {
          "call-calculator-1" => {
            "status" => "ok",
            "result" => { "value" => 4 },
            "output_chunks" => [],
            "summary_artifacts" => [],
          },
        }
      )
    )

    assert_equal({ "value" => 4 }, result.result)
    assert_equal "completed", tool_node.reload.lifecycle_state
    assert_equal "queued", join_node.reload.lifecycle_state
    assert_equal({ "value" => 4 }, tool_node.tool_invocations.sole.response_payload)
  end

  test "blocks the step for retry when the tool call references an unknown binding" do
    context = build_governed_tool_context!
    root_node = context.fetch(:workflow_node)

    Workflows::Mutate.call(
      workflow_run: root_node.workflow_run,
      nodes: [
        {
          node_key: "provider_round_1_tool_missing",
          node_type: "tool_call",
          decision_source: "llm",
          yielding_node_key: root_node.node_key,
          metadata: {},
          tool_call_payload: {
            "call_id" => "call-missing-1",
            "tool_name" => "missing_tool",
            "arguments" => {},
            "provider_format" => "chat_completions",
          },
        },
      ],
      edges: [
        {
          from_node_key: root_node.node_key,
          to_node_key: "provider_round_1_tool_missing",
        },
      ]
    )

    tool_node = root_node.workflow_run.reload.workflow_nodes.find_by!(node_key: "provider_round_1_tool_missing")

    result = ProviderExecution::ExecuteToolNode.call(workflow_node: tool_node)

    assert_equal tool_node.public_id, result.public_id
    assert_equal "waiting", tool_node.reload.lifecycle_state
    assert_equal "retryable_failure", root_node.workflow_run.reload.wait_reason_kind
    assert_equal "unknown_tool_reference", root_node.workflow_run.wait_failure_kind
    assert_equal "waiting", root_node.workflow_run.turn.reload.lifecycle_state
  end

  test "blocks the step when agent tool execution transport fails" do
    context = build_governed_tool_context!
    root_node = context.fetch(:workflow_node)
    source_binding = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: root_node,
      tool_catalog: [calculator_tool_entry]
    ).includes(:tool_definition, :tool_implementation).sole

    Workflows::Mutate.call(
      workflow_run: root_node.workflow_run,
      nodes: [
        {
          node_key: "provider_round_1_tool_timeout",
          node_type: "tool_call",
          decision_source: "llm",
          yielding_node_key: root_node.node_key,
          metadata: {},
          tool_call_payload: {
            "call_id" => "call-timeout-1",
            "tool_name" => "calculator",
            "arguments" => { "expression" => "2 + 2" },
            "provider_format" => "chat_completions",
          },
        },
      ],
      edges: [
        {
          from_node_key: root_node.node_key,
          to_node_key: "provider_round_1_tool_timeout",
        },
      ]
    )

    tool_node = root_node.workflow_run.reload.workflow_nodes.find_by!(node_key: "provider_round_1_tool_timeout")

    ToolBinding.create!(
      installation: tool_node.installation,
      workflow_node: tool_node,
      tool_definition: source_binding.tool_definition,
      tool_implementation: source_binding.tool_implementation,
      binding_reason: "snapshot_default",
      runtime_state: source_binding.runtime_state,
      round_scoped: source_binding.round_scoped,
      parallel_safe: source_binding.parallel_safe
    )

    result = ProviderExecution::ExecuteToolNode.call(
      workflow_node: tool_node,
      agent_request_exchange: Class.new do
        def execute_tool(*)
          raise ProviderExecution::AgentRequestExchange::TimeoutError.new(
            code: "mailbox_timeout",
            message: "timed out waiting for agent report",
            retryable: true
          )
        end
      end.new
    )

    assert_equal tool_node.public_id, result.public_id
    assert_equal "waiting", tool_node.reload.lifecycle_state
    assert_equal "external_dependency_blocked", root_node.workflow_run.reload.wait_reason_kind
    assert_equal "agent_transport_failed", root_node.workflow_run.wait_failure_kind
    assert_equal "automatic", root_node.workflow_run.wait_retry_strategy
  end

  test "execution-runtime tool calls enter waiting state after enqueuing runtime work" do
    runtime_tool = {
      "tool_name" => "memory_search",
      "tool_kind" => "execution_runtime",
      "implementation_source" => "execution_runtime",
      "implementation_ref" => "runtime/memory_search",
      "input_schema" => {
        "type" => "object",
        "properties" => {
          "query" => { "type" => "string" },
        },
      },
      "result_schema" => {
        "type" => "object",
        "properties" => {
          "entries" => { "type" => "array" },
        },
      },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
    context = build_governed_tool_context!(
      execution_runtime_tool_catalog: [runtime_tool],
      profile_policy: {
        "main" => {
          "label" => "Main",
          "description" => "Primary interactive profile",
          "allowed_tool_names" => %w[memory_search compact_context subagent_spawn],
        },
      }
    )
    root_node = context.fetch(:workflow_node)
    source_binding = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: root_node,
      tool_catalog: [runtime_tool]
    ).includes(:tool_definition, :tool_implementation).sole

    Workflows::Mutate.call(
      workflow_run: root_node.workflow_run,
      nodes: [
        {
          node_key: "provider_round_1_tool_runtime",
          node_type: "tool_call",
          decision_source: "llm",
          yielding_node_key: root_node.node_key,
          metadata: {},
          tool_call_payload: {
            "call_id" => "call-runtime-1",
            "tool_name" => "memory_search",
            "arguments" => { "query" => "skills" },
            "provider_format" => "chat_completions",
          },
        },
      ],
      edges: [
        {
          from_node_key: root_node.node_key,
          to_node_key: "provider_round_1_tool_runtime",
        },
      ]
    )

    tool_node = root_node.workflow_run.reload.workflow_nodes.find_by!(node_key: "provider_round_1_tool_runtime")

    ToolBinding.create!(
      installation: tool_node.installation,
      workflow_node: tool_node,
      tool_definition: source_binding.tool_definition,
      tool_implementation: source_binding.tool_implementation,
      binding_reason: "snapshot_default",
      runtime_state: source_binding.runtime_state,
      round_scoped: source_binding.round_scoped,
      parallel_safe: source_binding.parallel_safe
    )

    result = ProviderExecution::ExecuteToolNode.call(
      workflow_node: tool_node,
      execution_runtime_exchange: ProviderExecution::ExecutionRuntimeExchange.new(
        execution_runtime: root_node.turn.execution_runtime
      )
    )
    agent_task_run = AgentTaskRun.find_by!(workflow_node: tool_node, kind: "agent_tool_call")
    mailbox_item = AgentControlMailboxItem.find_by!(agent_task_run: agent_task_run, item_type: "execution_assignment")

    assert_equal tool_node.public_id, result.public_id
    assert_equal "waiting", tool_node.reload.lifecycle_state
    assert_equal "waiting", root_node.workflow_run.reload.wait_state
    assert_equal "execution_runtime_request", root_node.workflow_run.wait_reason_kind
    assert_equal "memory_search", mailbox_item.payload.fetch("tool_call").fetch("tool_name")
  end

  test "blocks the step for retry when agent tool execution returns an invalid contract" do
    context = build_governed_tool_context!
    root_node = context.fetch(:workflow_node)
    source_binding = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: root_node,
      tool_catalog: [calculator_tool_entry]
    ).includes(:tool_definition, :tool_implementation).sole

    Workflows::Mutate.call(
      workflow_run: root_node.workflow_run,
      nodes: [
        {
          node_key: "provider_round_1_tool_invalid_contract",
          node_type: "tool_call",
          decision_source: "llm",
          yielding_node_key: root_node.node_key,
          metadata: {},
          tool_call_payload: {
            "call_id" => "call-invalid-contract-1",
            "tool_name" => "calculator",
            "arguments" => { "expression" => "2 + 2" },
            "provider_format" => "chat_completions",
          },
        },
      ],
      edges: [
        {
          from_node_key: root_node.node_key,
          to_node_key: "provider_round_1_tool_invalid_contract",
        },
      ]
    )

    tool_node = root_node.workflow_run.reload.workflow_nodes.find_by!(node_key: "provider_round_1_tool_invalid_contract")

    ToolBinding.create!(
      installation: tool_node.installation,
      workflow_node: tool_node,
      tool_definition: source_binding.tool_definition,
      tool_implementation: source_binding.tool_implementation,
      binding_reason: "snapshot_default",
      runtime_state: source_binding.runtime_state,
      round_scoped: source_binding.round_scoped,
      parallel_safe: source_binding.parallel_safe
    )

    result = ProviderExecution::ExecuteToolNode.call(
      workflow_node: tool_node,
      agent_request_exchange: Class.new do
        def execute_tool(*)
          raise ProviderExecution::AgentRequestExchange::ProtocolError.new(
            code: "invalid_tool_result",
            message: "tool result payload must contain a status"
          )
        end
      end.new
    )

    assert_equal tool_node.public_id, result.public_id
    assert_equal "waiting", tool_node.reload.lifecycle_state
    assert_equal "retryable_failure", root_node.workflow_run.reload.wait_reason_kind
    assert_equal "invalid_agent_response_contract", root_node.workflow_run.wait_failure_kind
    assert_equal "automatic", root_node.workflow_run.wait_retry_strategy
  end

  test "leaves the tool invocation running while waiting on an agent receipt" do
    context = build_governed_tool_context!
    root_node = context.fetch(:workflow_node)
    source_binding = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: root_node,
      tool_catalog: [calculator_tool_entry]
    ).includes(:tool_definition, :tool_implementation).sole

    Workflows::Mutate.call(
      workflow_run: root_node.workflow_run,
      nodes: [
        {
          node_key: "provider_round_1_tool_pending",
          node_type: "tool_call",
          decision_source: "llm",
          yielding_node_key: root_node.node_key,
          metadata: {},
          tool_call_payload: {
            "call_id" => "call-pending-1",
            "tool_name" => "calculator",
            "arguments" => { "expression" => "2 + 2" },
            "provider_format" => "chat_completions",
          },
        },
      ],
      edges: [
        {
          from_node_key: root_node.node_key,
          to_node_key: "provider_round_1_tool_pending",
        },
      ]
    )

    tool_node = root_node.workflow_run.reload.workflow_nodes.find_by!(node_key: "provider_round_1_tool_pending")

    ToolBinding.create!(
      installation: tool_node.installation,
      workflow_node: tool_node,
      tool_definition: source_binding.tool_definition,
      tool_implementation: source_binding.tool_implementation,
      binding_reason: "snapshot_default",
      runtime_state: source_binding.runtime_state,
      round_scoped: source_binding.round_scoped,
      parallel_safe: source_binding.parallel_safe
    )

    result = ProviderExecution::ExecuteToolNode.call(
      workflow_node: tool_node,
      agent_request_exchange: ProviderExecution::AgentRequestExchange.new(
        agent_definition_version: context.fetch(:agent_definition_version),
        timeout: 0.001,
        poll_interval: 0.0,
        sleeper: ->(_duration) { },
      )
    )

    invocation = tool_node.tool_invocations.sole

    assert_equal tool_node.public_id, result.public_id
    assert_equal "waiting", tool_node.reload.lifecycle_state
    assert_equal "waiting", root_node.workflow_run.reload.wait_state
    assert_equal "agent_request", root_node.workflow_run.wait_reason_kind
    assert_equal "running", invocation.reload.status
  end

  test "does not restart a waiting tool node while its agent request is still pending" do
    context = build_governed_tool_context!
    root_node = context.fetch(:workflow_node)
    source_binding = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: root_node,
      tool_catalog: [calculator_tool_entry]
    ).includes(:tool_definition, :tool_implementation).sole

    Workflows::Mutate.call(
      workflow_run: root_node.workflow_run,
      nodes: [
        {
          node_key: "provider_round_1_tool_pending",
          node_type: "tool_call",
          decision_source: "llm",
          yielding_node_key: root_node.node_key,
          metadata: {},
          tool_call_payload: {
            "call_id" => "call-pending-1",
            "tool_name" => "calculator",
            "arguments" => { "expression" => "2 + 2" },
            "provider_format" => "chat_completions",
          },
        },
      ],
      edges: [
        {
          from_node_key: root_node.node_key,
          to_node_key: "provider_round_1_tool_pending",
        },
      ]
    )

    tool_node = root_node.workflow_run.reload.workflow_nodes.find_by!(node_key: "provider_round_1_tool_pending")

    ToolBinding.create!(
      installation: tool_node.installation,
      workflow_node: tool_node,
      tool_definition: source_binding.tool_definition,
      tool_implementation: source_binding.tool_implementation,
      binding_reason: "snapshot_default",
      runtime_state: source_binding.runtime_state,
      round_scoped: source_binding.round_scoped,
      parallel_safe: source_binding.parallel_safe
    )

    exchange = ProviderExecution::AgentRequestExchange.new(
      agent_definition_version: context.fetch(:agent_definition_version),
      timeout: 30.seconds,
      poll_interval: 0.0,
      sleeper: ->(_duration) { }
    )

    ProviderExecution::ExecuteToolNode.call(
      workflow_node: tool_node,
      agent_request_exchange: exchange
    )

    waiting_node = tool_node.reload
    waiting_started_at = waiting_node.started_at

    result = ProviderExecution::ExecuteToolNode.call(
      workflow_node: waiting_node,
      agent_request_exchange: exchange
    )

    assert_equal waiting_node.public_id, result.public_id
    assert_equal "waiting", result.reload.lifecycle_state
    assert_equal waiting_started_at, result.started_at
    assert_equal "waiting", root_node.workflow_run.reload.wait_state
  end

  test "re-blocks the workflow when a pending agent tool request is resumed before its terminal receipt arrives" do
    context = build_governed_tool_context!
    root_node = context.fetch(:workflow_node)
    source_binding = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: root_node,
      tool_catalog: [calculator_tool_entry]
    ).includes(:tool_definition, :tool_implementation).sole

    Workflows::Mutate.call(
      workflow_run: root_node.workflow_run,
      nodes: [
        {
          node_key: "provider_round_1_tool_pending",
          node_type: "tool_call",
          decision_source: "llm",
          yielding_node_key: root_node.node_key,
          metadata: {},
          tool_call_payload: {
            "call_id" => "call-pending-1",
            "tool_name" => "calculator",
            "arguments" => { "expression" => "2 + 2" },
            "provider_format" => "chat_completions",
          },
        },
      ],
      edges: [
        {
          from_node_key: root_node.node_key,
          to_node_key: "provider_round_1_tool_pending",
        },
      ]
    )

    tool_node = root_node.workflow_run.reload.workflow_nodes.find_by!(node_key: "provider_round_1_tool_pending")

    ToolBinding.create!(
      installation: tool_node.installation,
      workflow_node: tool_node,
      tool_definition: source_binding.tool_definition,
      tool_implementation: source_binding.tool_implementation,
      binding_reason: "snapshot_default",
      runtime_state: source_binding.runtime_state,
      round_scoped: source_binding.round_scoped,
      parallel_safe: source_binding.parallel_safe
    )

    exchange = ProviderExecution::AgentRequestExchange.new(
      agent_definition_version: context.fetch(:agent_definition_version),
      timeout: 30.seconds,
      poll_interval: 0.0,
      sleeper: ->(_duration) { }
    )

    ProviderExecution::ExecuteToolNode.call(workflow_node: tool_node, agent_request_exchange: exchange)
    Workflows::ResumeBlockedStep.call(workflow_run: root_node.workflow_run.reload)

    result = ProviderExecution::ExecuteToolNode.call(
      workflow_node: tool_node.reload,
      agent_request_exchange: exchange
    )

    assert_equal tool_node.public_id, result.public_id
    assert_equal "waiting", result.reload.lifecycle_state
    assert_equal "waiting", root_node.workflow_run.reload.wait_state
    assert_equal "agent_request", root_node.workflow_run.wait_reason_kind
  end

  private

  def calculator_tool_entry
    {
      "tool_name" => "calculator",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "fenix/calculator",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
  end
end
