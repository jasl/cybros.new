require "test_helper"

class WorkflowRunTest < ActiveSupport::TestCase
  test "enforces one workflow per turn and one active workflow per conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    first_run = create_workflow_run!(turn: first_turn)
    duplicate_turn_run = WorkflowRun.new(
      installation: conversation.installation,
      conversation: conversation,
      turn: first_turn,
      lifecycle_state: "completed"
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    competing_active_run = WorkflowRun.new(
      installation: conversation.installation,
      conversation: conversation,
      turn: second_turn,
      lifecycle_state: "active"
    )

    assert first_run.active?
    assert_not duplicate_turn_run.valid?
    assert_includes duplicate_turn_run.errors[:turn_id], "has already been taken"
    assert_not competing_active_run.valid?
    assert_includes competing_active_run.errors[:conversation], "already has an active workflow"
  end
end
