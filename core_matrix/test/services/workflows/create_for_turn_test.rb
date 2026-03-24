require "test_helper"

class Workflows::CreateForTurnTest < ActiveSupport::TestCase
  test "creates one active workflow with a root node for the turn" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: { "policy_sensitive" => true }
    )

    assert workflow_run.active?
    assert_equal turn, workflow_run.turn
    assert_equal 1, workflow_run.workflow_nodes.count
    assert_equal "root", workflow_run.workflow_nodes.first.node_key
    assert_equal 0, workflow_run.workflow_nodes.first.ordinal
  end

  test "rejects a second active workflow in the same conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    Workflows::CreateForTurn.call(
      turn: first_turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {}
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::CreateForTurn.call(
        turn: second_turn,
        root_node_key: "root-2",
        root_node_type: "turn_root",
        decision_source: "system",
        metadata: {}
      )
    end
  end
end
