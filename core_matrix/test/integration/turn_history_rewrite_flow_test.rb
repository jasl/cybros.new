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
      content: "Second output alternative",
      source_input_message: retried_turn.selected_input_message
    )
    retried_turn.update!(lifecycle_state: "completed")
    Turns::SelectOutputVariant.call(message: alternative_output)

    Conversations::RollbackToTurn.call(conversation: conversation, turn: first_turn)
    edited_turn = Turns::EditTailInput.call(turn: first_turn, content: "First input revised")
    branch_rerun = Turns::RerunOutput.call(message: first_output, content: "Branch rerun output")

    assert_equal "First input revised", edited_turn.selected_input_message.content
    assert_nil edited_turn.selected_output_message
    assert_equal "Second output alternative", retried_turn.reload.selected_output_message.content
    assert_equal retried_turn.reload.selected_input_message, retried_turn.selected_output_message.source_input_message
    assert branch_rerun.conversation.branch?
    assert_equal "First input", branch_rerun.selected_input_message.content
    assert_equal "Branch rerun output", branch_rerun.selected_output_message.content
    assert_equal branch_rerun.selected_input_message, branch_rerun.selected_output_message.source_input_message
  end

  test "retry and rerun fail closed when selected output provenance is missing" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    failed_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Failed input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    failed_output = attach_selected_output!(failed_turn, content: "Failed output")
    failed_turn.update!(lifecycle_state: "failed")
    failed_output.update_columns(source_input_message_id: nil)

    retry_error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::RetryOutput.call(message: failed_output.reload, content: "Retried output")
    end

    completed_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Completed input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    completed_output = attach_selected_output!(completed_turn, content: "Completed output")
    completed_turn.update!(lifecycle_state: "completed")
    completed_output.update_columns(source_input_message_id: nil)

    rerun_error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::RerunOutput.call(message: completed_output.reload, content: "Rerun output")
    end

    assert_includes retry_error.record.errors[:selected_output_message], "must carry source input provenance"
    assert_includes rerun_error.record.errors[:selected_output_message], "must carry source input provenance"
  end
end
