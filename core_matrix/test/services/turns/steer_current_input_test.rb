require "test_helper"

class Turns::SteerCurrentInputTest < ActiveSupport::TestCase
  test "creates a new selected input variant for the active turn" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(workspace: context[:workspace]),
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    steered = Turns::SteerCurrentInput.call(
      turn: turn,
      content: "Revised input"
    )

    assert_equal turn.id, steered.id
    assert_equal "Revised input", steered.selected_input_message.content
    assert_equal 1, steered.selected_input_message.variant_index
    assert_equal ["Original input", "Revised input"],
      UserMessage.where(turn: turn).order(:variant_index).pluck(:content)
  end
end
