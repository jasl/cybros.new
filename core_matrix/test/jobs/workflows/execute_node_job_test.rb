require "test_helper"

class Workflows::ExecuteNodeJobTest < ActiveSupport::TestCase
  test "skips a workflow node that is already terminal" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Node job input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(
      turn: turn,
      lifecycle_state: "active"
    )
    workflow_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "node",
      node_type: "turn_step",
      decision_source: "agent_program",
      metadata: {}
    )

    complete_workflow_node!(workflow_node)

    assert_equal "completed", workflow_node.reload.lifecycle_state

    Workflows::ExecuteNodeJob.perform_now(workflow_node.public_id)

    assert_equal "completed", workflow_node.reload.lifecycle_state
  end

  private

  def complete_workflow_node!(workflow_node)
    workflow_node.update!(
      lifecycle_state: "completed",
      started_at: 1.minute.ago,
      finished_at: Time.current
    )
  end
end
