require "test_helper"

class Turns::RetryOutputTest < ActiveSupport::TestCase
  test "retries a failed output by creating a new output variant in the same turn" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    ),
      content: "Input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output = attach_selected_output!(turn, content: "Failed output")
    turn.update!(lifecycle_state: "failed")

    retried = Turns::RetryOutput.call(
      message: output,
      content: "Retried output"
    )

    assert_equal turn.id, retried.id
    assert retried.active?
    assert_equal "Retried output", retried.selected_output_message.content
    assert_equal 1, retried.selected_output_message.variant_index
    assert_equal turn.selected_input_message, retried.selected_output_message.source_input_message
  end

  test "rejects retrying output on a turn superseded by rollback" do
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
    attach_selected_output!(first_turn, content: "First output")
    first_turn.update!(lifecycle_state: "completed")

    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output = attach_selected_output!(second_turn, content: "Second output")
    second_turn.update!(lifecycle_state: "failed")

    Conversations::RollbackToTurn.call(conversation: conversation, turn: first_turn)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::RetryOutput.call(
        message: output.reload,
        content: "Should stay superseded"
      )
    end

    assert_includes error.record.errors[:base], "must target the selected tail output"
    assert second_turn.reload.canceled?
    assert_equal output, second_turn.selected_output_message
    assert_equal [output.id], second_turn.messages.where(slot: "output").order(:variant_index).pluck(:id)
  end

  test "rejects retrying output after the turn has been interrupted" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    ),
      content: "Input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output = attach_selected_output!(turn, content: "Interrupted output")
    turn.update!(
      lifecycle_state: "canceled",
      cancellation_reason_kind: "turn_interrupted",
      cancellation_requested_at: Time.current
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::RetryOutput.call(
        message: output,
        content: "Should not rewrite"
      )
    end

    assert_includes error.record.errors[:base], "must not rewrite output after turn interruption"
  end

  test "rejects retrying output when the target output is missing source input provenance" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    ),
      content: "Input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output = attach_selected_output!(turn, content: "Failed output")
    turn.update!(lifecycle_state: "failed")
    output.update_columns(source_input_message_id: nil)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::RetryOutput.call(
        message: output.reload,
        content: "Should fail"
      )
    end

    assert_includes error.record.errors[:selected_output_message], "must carry source input provenance"
  end
end
