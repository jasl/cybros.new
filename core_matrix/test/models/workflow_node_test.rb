require "test_helper"

class WorkflowNodeTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run)

    assert workflow_node.public_id.present?
    assert workflow_node.pending?
    assert_equal workflow_node, WorkflowNode.find_by_public_id!(workflow_node.public_id)
  end

  test "tracks unique ordinals decision sources and audit metadata" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
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

  test "persists frozen presentation policy and yield linkage independently from node type" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    yielding_node = create_workflow_node!(
      workflow_run: workflow_run,
      ordinal: 0,
      node_key: "agent_step_1",
      node_type: "agent_task_run",
      presentation_policy: "ops_trackable"
    )

    title_update_node = WorkflowNode.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      workspace: conversation.workspace,
      conversation: conversation,
      turn: turn,
      yielding_workflow_node: yielding_node,
      ordinal: 1,
      node_key: "title-update",
      node_type: "conversation_title_update",
      intent_kind: "conversation_title_update",
      stage_index: 0,
      stage_position: 0,
      presentation_policy: "internal_only",
      decision_source: "agent_program",
      metadata: {}
    )
    operator_node = WorkflowNode.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      workspace: conversation.workspace,
      conversation: conversation,
      turn: turn,
      yielding_workflow_node: yielding_node,
      ordinal: 2,
      node_key: "title-update-ops",
      node_type: "conversation_title_update",
      intent_kind: "conversation_title_update",
      stage_index: 0,
      stage_position: 1,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      metadata: {}
    )

    assert title_update_node.internal_only?
    assert operator_node.ops_trackable?
    assert_equal yielding_node, title_update_node.yielding_workflow_node
    assert_equal conversation.workspace, title_update_node.workspace
    assert_equal conversation, title_update_node.conversation
    assert_equal turn, title_update_node.turn
  end
end
