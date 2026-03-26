require "test_helper"

class Turns::EditTailInputTest < ActiveSupport::TestCase
  test "creates a new selected input variant without mutating historical rows" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    ),
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Old output")

    edited = Turns::EditTailInput.call(
      turn: turn,
      content: "Edited input"
    )

    assert_equal turn.id, edited.id
    assert_equal "Edited input", edited.selected_input_message.content
    assert_equal 1, edited.selected_input_message.variant_index
    assert_nil edited.selected_output_message
    assert_equal ["Original input", "Edited input"],
      UserMessage.where(turn: turn).order(:variant_index).pluck(:content)
  end

  test "rejects editing a non tail input without rollback or fork semantics" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    historical_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Historical input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    historical_turn.update!(lifecycle_state: "completed")
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Turns::EditTailInput.call(turn: historical_turn, content: "Should fail")
    end
  end
end
