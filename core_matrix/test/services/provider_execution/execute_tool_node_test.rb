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
          metadata: {
            "tool_call" => {
              "call_id" => "call-calculator-1",
              "tool_name" => "calculator",
              "arguments" => { "expression" => "2 + 2" },
              "provider_format" => "chat_completions",
            },
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
      binding_payload: source_binding.binding_payload
    )

    result = ProviderExecution::ExecuteToolNode.call(
      workflow_node: tool_node,
      program_exchange: ProviderExecutionTestSupport::FakeProgramExchange.new(
        program_tool_results: {
          "call-calculator-1" => {
            "status" => "completed",
            "result" => { "value" => 4 },
          },
        }
      )
    )

    assert_equal({ "value" => 4 }, result.result)
    assert_equal "completed", tool_node.reload.lifecycle_state
    assert_equal "queued", join_node.reload.lifecycle_state
    assert_equal({ "value" => 4 }, tool_node.tool_invocations.sole.response_payload)
  end

  private

  def calculator_tool_entry
    {
      "tool_name" => "calculator",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "fenix/runtime/calculator",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
  end
end
