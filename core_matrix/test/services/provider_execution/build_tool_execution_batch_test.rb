require "test_helper"

class ProviderExecution::BuildToolExecutionBatchTest < ActiveSupport::TestCase
  test "packs consecutive parallel-safe tool calls into one parallel stage" do
    context = build_governed_tool_context!
    workflow_node = context.fetch(:workflow_node)
    bindings = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: workflow_node,
      tool_catalog: [
        calculator_tool_entry(parallel_safe: true),
        search_tool_entry(parallel_safe: true),
      ]
    ).includes(:tool_definition, :tool_implementation).to_a

    batch = ProviderExecution::BuildToolExecutionBatch.call(
      workflow_node: workflow_node,
      tool_calls: [
        tool_call("call-1", "calculator", expression: "2 + 2"),
        tool_call("call-2", "search_docs", query: "parallel"),
      ],
      round_bindings: bindings
    )

    assert_equal 1, batch.fetch("stages").length
    assert_equal "parallel", batch.fetch("stages").first.fetch("dispatch_mode")
    assert_equal %w[provider_round_1_tool_1 provider_round_1_tool_2], batch.fetch("ordered_tool_node_keys")
    assert_equal 2, batch.fetch("successor").fetch("provider_round_index")
    assert_equal %w[provider_round_1_tool_1 provider_round_1_tool_2], batch.fetch("successor").fetch("prior_tool_node_keys")
  end

  test "splits unsafe tool calls into separate serial stages" do
    context = build_governed_tool_context!
    workflow_node = context.fetch(:workflow_node)
    bindings = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: workflow_node,
      tool_catalog: [
        calculator_tool_entry(parallel_safe: true),
        file_write_tool_entry,
        search_tool_entry(parallel_safe: true),
      ]
    ).includes(:tool_definition, :tool_implementation).to_a

    batch = ProviderExecution::BuildToolExecutionBatch.call(
      workflow_node: workflow_node,
      tool_calls: [
        tool_call("call-1", "calculator", expression: "2 + 2"),
        tool_call("call-2", "workspace_write_file", path: "notes.txt"),
        tool_call("call-3", "search_docs", query: "graph"),
      ],
      round_bindings: bindings
    )

    assert_equal %w[serial serial serial], batch.fetch("stages").map { |stage| stage.fetch("dispatch_mode") }
    assert_equal %w[provider_round_1_tool_1 provider_round_1_tool_2 provider_round_1_tool_3], batch.fetch("ordered_tool_node_keys")
  end

  private

  def tool_call(call_id, tool_name, arguments = {})
    {
      "call_id" => call_id,
      "tool_name" => tool_name,
      "arguments" => arguments.deep_stringify_keys,
      "provider_format" => "chat_completions",
    }
  end

  def calculator_tool_entry(parallel_safe:)
    {
      "tool_name" => "calculator",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "fenix/agent/calculator",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
      "execution_policy" => { "parallel_safe" => parallel_safe },
    }
  end

  def search_tool_entry(parallel_safe:)
    {
      "tool_name" => "search_docs",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "fenix/agent/search_docs",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
      "execution_policy" => { "parallel_safe" => parallel_safe },
    }
  end

  def file_write_tool_entry
    {
      "tool_name" => "workspace_write_file",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "fenix/agent/workspace_write_file",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
  end
end
