require "test_helper"

class WorkflowGraphFlowTest < ActionDispatch::IntegrationTest
  test "workflow graphs stay turn scoped and expand without replacing the run" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {}
    )
    Workflows::Mutate.call(
      workflow_run: workflow_run,
      nodes: [
        {
          node_key: "llm",
          node_type: "llm_call",
          decision_source: "llm",
          metadata: { "policy_sensitive" => true },
        },
      ],
      edges: [
        { from_node_key: "root", to_node_key: "llm" },
      ]
    )
    expanded = Workflows::Mutate.call(
      workflow_run: workflow_run,
      nodes: [
        {
          node_key: "tool",
          node_type: "tool_call",
          decision_source: "agent_program",
          metadata: {},
        },
        {
          node_key: "handoff",
          node_type: "handoff",
          decision_source: "user",
          metadata: {},
        },
      ],
      edges: [
        { from_node_key: "llm", to_node_key: "tool" },
        { from_node_key: "tool", to_node_key: "handoff" },
      ]
    )

    assert_equal workflow_run.id, expanded.id
    assert_equal turn, expanded.turn
    assert_equal 1, conversation.workflow_runs.count
    assert_equal 4, expanded.workflow_nodes.count
    assert_equal 3, expanded.workflow_edges.count
    assert_equal %w[root llm tool handoff], expanded.workflow_nodes.order(:ordinal).pluck(:node_key)
  end
end
