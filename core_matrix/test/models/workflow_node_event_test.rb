require "test_helper"

class WorkflowNodeEventTest < ActiveSupport::TestCase
  test "preserves ordered live output and status replay events per workflow node" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Event input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run)

    output_event = WorkflowNodeEvent.create!(
      installation: context[:installation],
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      ordinal: 0,
      event_kind: "output_delta",
      payload: { "delta" => "hello" }
    )
    status_event = WorkflowNodeEvent.create!(
      installation: context[:installation],
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      ordinal: 1,
      event_kind: "status",
      payload: { "state" => "running" }
    )

    assert_equal [output_event, status_event], WorkflowNodeEvent.where(workflow_node: workflow_node).order(:ordinal).to_a

    duplicate = WorkflowNodeEvent.new(
      installation: context[:installation],
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      ordinal: 1,
      event_kind: "status",
      payload: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:ordinal], "has already been taken"
  end

  test "copies projection metadata from the workflow node for audit-only intent outcomes" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Event input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(
      workflow_run: workflow_run,
      presentation_policy: "ops_trackable"
    )

    event = WorkflowNodeEvent.create!(
      installation: context[:installation],
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      ordinal: 0,
      event_kind: "intent_rejected",
      payload: {
        "intent_id" => "intent-1",
        "intent_kind" => "subagent_spawn",
        "reason" => "parallel_conflict",
      }
    )

    assert_equal conversation.workspace, event.workspace
    assert_equal conversation, event.conversation
    assert_equal turn, event.turn
    assert_equal workflow_node.node_key, event.workflow_node_key
    assert_equal workflow_node.ordinal, event.workflow_node_ordinal
    assert_equal "ops_trackable", event.presentation_policy
  end
end
