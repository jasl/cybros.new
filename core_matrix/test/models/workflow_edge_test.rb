require "test_helper"

class WorkflowEdgeTest < ActiveSupport::TestCase
  test "enforces edge ordering and same workflow integrity" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    root_node = create_workflow_node!(workflow_run: workflow_run, ordinal: 0, node_key: "root")
    child_node = create_workflow_node!(workflow_run: workflow_run, ordinal: 1, node_key: "child")
    edge = create_workflow_edge!(
      workflow_run: workflow_run,
      from_node: root_node,
      to_node: child_node,
      ordinal: 0
    )
    other_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    other_turn = Turns::StartUserTurn.call(
      conversation: other_conversation,
      content: "Other input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    other_run = create_workflow_run!(turn: other_turn, lifecycle_state: "completed")
    foreign_node = create_workflow_node!(workflow_run: other_run, ordinal: 0, node_key: "foreign")
    invalid_edge = WorkflowEdge.new(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      from_node: root_node,
      to_node: foreign_node,
      ordinal: 1
    )

    assert_equal 0, edge.ordinal
    assert edge.required?
    assert_not invalid_edge.valid?
    assert_includes invalid_edge.errors[:to_node], "must belong to the same workflow"
  end
end
