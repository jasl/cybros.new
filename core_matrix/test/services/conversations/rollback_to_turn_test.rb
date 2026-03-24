require "test_helper"

class Conversations::RollbackToTurnTest < ActiveSupport::TestCase
  test "cancels later turns so the target turn becomes the active tail" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    first_turn.update!(lifecycle_state: "completed")
    attach_selected_output!(first_turn, content: "First output")

    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    restored = Conversations::RollbackToTurn.call(
      conversation: conversation,
      turn: first_turn
    )

    assert_equal first_turn, restored
    assert second_turn.reload.canceled?
    assert restored.reload.tail_in_active_timeline?
  end
end
