require "test_helper"

class TurnHistoryRewriteFlowTest < ActionDispatch::IntegrationTest
  test "rollback edit retry rerun and variant selection stay append only" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    first_output = attach_selected_output!(first_turn, content: "First output")
    first_turn.update!(lifecycle_state: "completed")

    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_output = attach_selected_output!(second_turn, content: "Second output")
    second_turn.update!(lifecycle_state: "failed")

    retried_turn = Turns::RetryOutput.call(message: second_output, content: "Second output retry")
    retried_turn.update!(lifecycle_state: "completed")
    alternative_output = AgentMessage.create!(
      installation: retried_turn.installation,
      conversation: retried_turn.conversation,
      turn: retried_turn,
      role: "agent",
      slot: "output",
      variant_index: 2,
      content: "Second output alternative"
    )
    retried_turn.update!(lifecycle_state: "completed")
    Turns::SelectOutputVariant.call(message: alternative_output)

    Conversations::RollbackToTurn.call(conversation: conversation, turn: first_turn)
    edited_turn = Turns::EditTailInput.call(turn: first_turn, content: "First input revised")
    branch_rerun = Turns::RerunOutput.call(message: first_output, content: "Branch rerun output")

    assert_equal "First input revised", edited_turn.selected_input_message.content
    assert_nil edited_turn.selected_output_message
    assert_equal "Second output alternative", retried_turn.reload.selected_output_message.content
    assert branch_rerun.conversation.branch?
    assert_equal "Branch rerun output", branch_rerun.selected_output_message.content
  end
end
