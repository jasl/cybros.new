require "test_helper"

class ProviderExecution::RouteToolCallTest < ActiveSupport::TestCase
  setup do
    @mcp_server = FakeStreamableHttpMcpServer.new.start
  end

  teardown do
    @mcp_server.shutdown
  end

  test "routes agent-owned round tools back through the program mailbox exchange with workflow-node durable proof" do
    context = build_governed_tool_context!(
      agent_tool_catalog: governed_agent_tool_catalog + [calculator_tool_entry],
      profile_catalog: governed_profile_catalog.deep_merge(
        "main" => {
          "allowed_tool_names" => %w[exec_command compact_context subagent_spawn calculator],
        }
      )
    )
    workflow_node = context.fetch(:workflow_node)
    round_bindings = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: workflow_node,
      tool_catalog: [calculator_tool_entry]
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      program_tool_results: {
        "call-calculator-1" => {
          "status" => "ok",
          "result" => { "value" => 4 },
          "output_chunks" => [],
          "summary_artifacts" => [{ "kind" => "tool_batch", "label" => "Calculator", "text" => "4", "metadata" => {} }],
        },
      }
    )

    result = ProviderExecution::RouteToolCall.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-calculator-1",
        "tool_name" => "calculator",
        "arguments" => { "expression" => "2 + 2" },
        "provider_format" => "chat_completions",
      },
      round_bindings: round_bindings,
      program_exchange: program_exchange
    )

    invocation = result.tool_invocation.reload

    assert_equal({ "value" => 4 }, result.result)
    assert_equal "succeeded", invocation.status
    assert_equal workflow_node, invocation.workflow_node
    assert_nil invocation.agent_task_run
    assert_equal({ "expression" => "2 + 2" }, invocation.request_payload.fetch("arguments"))
    assert_equal({ "value" => 4 }, invocation.response_payload)
    assert_equal "call-calculator-1", program_exchange.execute_program_tool_requests.first.fetch("program_tool_call").fetch("call_id")
    assert_equal workflow_node.public_id, program_exchange.execute_program_tool_requests.first.fetch("task").fetch("workflow_node_id")
    assert_equal(
      { "deployment_public_id" => context.fetch(:deployment).public_id },
      program_exchange.execute_program_tool_requests.first.fetch("runtime_context").slice("deployment_public_id")
    )
  end

  test "routes execution-environment round tools back through the program mailbox exchange" do
    environment_tool = {
      "tool_name" => "memory_search",
      "tool_kind" => "environment_runtime",
      "implementation_source" => "execution_environment",
      "implementation_ref" => "env/memory_search",
      "input_schema" => {
        "type" => "object",
        "properties" => {
          "query" => { "type" => "string" },
          "limit" => { "type" => "integer" },
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
      environment_tool_catalog: [environment_tool],
      profile_catalog: {
        "main" => {
          "label" => "Main",
          "description" => "Primary interactive profile",
          "allowed_tool_names" => %w[memory_search compact_context subagent_spawn],
        },
      }
    )
    workflow_node = context.fetch(:workflow_node)
    round_bindings = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: workflow_node,
      tool_catalog: [environment_tool]
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      program_tool_results: {
        "call-memory-search-1" => {
          "status" => "ok",
          "result" => {
            "entries" => [
              { "id" => "memory-1", "content" => "Using superpowers enables skill routing." },
            ],
          },
          "output_chunks" => [],
          "summary_artifacts" => [],
        },
      }
    )

    result = ProviderExecution::RouteToolCall.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-memory-search-1",
        "tool_name" => "memory_search",
        "arguments" => { "query" => "using-superpowers skill", "limit" => 5 },
        "provider_format" => "chat_completions",
      },
      round_bindings: round_bindings,
      program_exchange: program_exchange
    )

    invocation = result.tool_invocation.reload

    assert_equal(
      { "entries" => [{ "id" => "memory-1", "content" => "Using superpowers enables skill routing." }] },
      result.result
    )
    assert_equal "succeeded", invocation.status
    assert_equal workflow_node, invocation.workflow_node
    assert_equal "memory_search", invocation.tool_definition.tool_name
    assert_equal "call-memory-search-1", program_exchange.execute_program_tool_requests.first.fetch("program_tool_call").fetch("call_id")
    assert_equal "memory_search", program_exchange.execute_program_tool_requests.first.fetch("program_tool_call").fetch("tool_name")
  end

  test "routes round-visible MCP tools through the generic MCP executor" do
    context = build_governed_mcp_context!(base_url: @mcp_server.base_url)
    workflow_node = context.fetch(:workflow_node)
    round_bindings = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: workflow_node,
      tool_catalog: governed_mcp_tool_catalog(base_url: @mcp_server.base_url)
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a

    result = ProviderExecution::RouteToolCall.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-mcp-1",
        "tool_name" => "remote_echo",
        "arguments" => { "message" => "hello from loop" },
        "provider_format" => "chat_completions",
      },
      round_bindings: round_bindings
    )

    invocation = result.tool_invocation.reload

    assert_equal "succeeded", invocation.status
    assert_equal workflow_node, invocation.workflow_node
    assert_equal "echo: hello from loop", result.result.dig("content", 0, "text")
    assert_match(/\Asession-\d+\z/, result.tool_binding.reload.binding_payload.dig("mcp", "session_id"))
  end

  test "routes core matrix tools without delegating back to the program mailbox exchange" do
    context = build_governed_tool_context!(
      profile_catalog: {
        "main" => {
          "label" => "Main",
          "description" => "Primary interactive profile",
          "allowed_tool_names" => %w[exec_command compact_context subagent_spawn subagent_list],
        },
      }
    )
    workflow_node = context.fetch(:workflow_node)
    round_bindings = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: workflow_node
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new

    result = ProviderExecution::RouteToolCall.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-subagent-list-1",
        "tool_name" => "subagent_list",
        "arguments" => {},
        "provider_format" => "chat_completions",
      },
      round_bindings: round_bindings,
      program_exchange: program_exchange
    )

    invocation = result.tool_invocation.reload

    assert_equal({ "entries" => [] }, result.result)
    assert_equal "succeeded", invocation.status
    assert_equal workflow_node, invocation.workflow_node
    assert_equal "subagent_list", invocation.tool_definition.tool_name
    assert_equal [], program_exchange.execute_program_tool_requests
  end

  private

  def calculator_tool_entry
    {
      "tool_name" => "calculator",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "fenix/runtime/calculator",
      "input_schema" => {
        "type" => "object",
        "properties" => {
          "expression" => { "type" => "string" },
        },
      },
      "result_schema" => {
        "type" => "object",
        "properties" => {
          "value" => { "type" => "integer" },
        },
      },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
  end
end
