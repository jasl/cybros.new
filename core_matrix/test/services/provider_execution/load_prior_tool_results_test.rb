require "test_helper"

class ProviderExecution::LoadPriorToolResultsTest < ActiveSupport::TestCase
  test "rebuilds prior tool results from ordered predecessor tool nodes" do
    context = build_governed_tool_context!
    root_node = context.fetch(:workflow_node)
    tool_bindings = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: root_node,
      tool_catalog: [compact_context_tool_entry]
    ).includes(:tool_definition, :tool_implementation).to_a
    source_binding = tool_bindings.sole

    tool_node = nil
    successor = nil

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
            "call_id" => "call-compact-context-1",
            "tool_name" => "compact_context",
            "arguments" => compact_context_tool_arguments,
            "provider_format" => "chat_completions",
            "provider_payload" => { "thoughtSignature" => "sig_123" },
          },
        },
        {
          node_key: "provider_round_2",
          node_type: "turn_step",
          decision_source: "system",
          provider_round_index: 2,
          prior_tool_node_keys: ["provider_round_1_tool_1"],
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
          to_node_key: "provider_round_2",
        },
      ]
    )

    tool_node = root_node.workflow_run.reload.workflow_nodes.find_by!(node_key: "provider_round_1_tool_1")
    successor = root_node.workflow_run.workflow_nodes.find_by!(node_key: "provider_round_2")

    binding = ToolBinding.create!(
      installation: tool_node.installation,
      workflow_node: tool_node,
      tool_definition: source_binding.tool_definition,
      tool_implementation: source_binding.tool_implementation,
      binding_reason: "snapshot_default",
      runtime_state: source_binding.runtime_state,
      round_scoped: source_binding.round_scoped,
      parallel_safe: source_binding.parallel_safe
    )
    invocation = ToolInvocations::Provision.call(
      tool_binding: binding,
      request_payload: {
        "arguments" => compact_context_tool_arguments,
      },
      idempotency_key: "call-compact-context-1"
    ).tool_invocation
    ToolInvocations::Complete.call(
      tool_invocation: invocation,
      response_payload: compact_context_tool_result
    )

    prior_tool_results = ProviderExecution::LoadPriorToolResults.call(workflow_node: successor)

    assert_equal 1, prior_tool_results.length
    assert_equal "call-compact-context-1", prior_tool_results.first.fetch("tool_call_id")
    assert_equal({ "thoughtSignature" => "sig_123" }, prior_tool_results.first.fetch("provider_payload"))
    assert_equal(compact_context_tool_result, prior_tool_results.first.fetch("result"))
  end
end
