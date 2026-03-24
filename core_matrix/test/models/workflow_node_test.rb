require "test_helper"

class WorkflowNodeTest < ActiveSupport::TestCase
  test "tracks unique ordinals decision sources and audit metadata" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    node = create_workflow_node!(
      workflow_run: workflow_run,
      ordinal: 0,
      node_key: "root",
      node_type: "turn_root",
      decision_source: "system",
      metadata: { "policy_sensitive" => true }
    )
    duplicate_ordinal = WorkflowNode.new(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      ordinal: 0,
      node_key: "duplicate",
      node_type: "llm_call",
      decision_source: "llm",
      metadata: {}
    )

    assert node.system?
    assert_equal true, node.metadata["policy_sensitive"]
    assert_not duplicate_ordinal.valid?
    assert_includes duplicate_ordinal.errors[:ordinal], "has already been taken"
  end
end
