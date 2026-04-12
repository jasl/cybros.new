require "test_helper"

class Workflows::MutateTest < ActiveSupport::TestCase
  test "appends nodes and edges without replacing the workflow run" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
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

    first_mutation = Workflows::Mutate.call(
      workflow_run: workflow_run,
      nodes: [
        {
          node_key: "llm",
          node_type: "llm_call",
          decision_source: "llm",
          metadata: { "policy_sensitive" => true },
        },
        {
          node_key: "tool",
          node_type: "tool_call",
          decision_source: "agent",
          metadata: {},
        },
      ],
      edges: [
        { from_node_key: "root", to_node_key: "llm" },
        { from_node_key: "root", to_node_key: "tool" },
      ]
    )
    second_mutation = Workflows::Mutate.call(
      workflow_run: workflow_run,
      nodes: [
        {
          node_key: "review",
          node_type: "review_gate",
          decision_source: "user",
          metadata: {},
        },
      ],
      edges: [
        { from_node_key: "llm", to_node_key: "review" },
      ]
    )

    assert_equal workflow_run.id, first_mutation.id
    assert_equal workflow_run.id, second_mutation.id
    assert_equal %w[root llm tool review], workflow_run.reload.workflow_nodes.order(:ordinal).pluck(:node_key)
    assert_equal [0, 1], workflow_run.workflow_edges.where(from_node: workflow_run.workflow_nodes.find_by!(node_key: "root")).order(:ordinal).pluck(:ordinal)
  end

  test "rejects mutations that would introduce a cycle" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
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
          metadata: {},
        },
      ],
      edges: [
        { from_node_key: "root", to_node_key: "llm" },
      ]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::Mutate.call(
        workflow_run: workflow_run,
        edges: [
          { from_node_key: "llm", to_node_key: "root" },
        ]
      )
    end

    assert_includes error.record.errors[:base], "must remain acyclic after mutation"
  end

  test "rejects edges that reference unknown workflow node keys" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
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

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::Mutate.call(
        workflow_run: workflow_run,
        edges: [
          { from_node_key: "root", to_node_key: "missing" },
        ]
      )
    end

    assert_includes error.record.errors[:base], "references unknown workflow node key missing"
  end
end
