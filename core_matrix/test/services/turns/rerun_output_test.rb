require "test_helper"

class Turns::RerunOutputTest < ActiveSupport::TestCase
  test "reruns a finished tail output in place by creating a new output variant" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    ),
      content: "Input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output = attach_selected_output!(turn, content: "Original output")
    turn.update!(lifecycle_state: "completed")

    rerun = Turns::RerunOutput.call(
      message: output,
      content: "Rerun output"
    )

    assert_equal turn.id, rerun.id
    assert rerun.active?
    assert_equal "Rerun output", rerun.selected_output_message.content
    assert_equal 1, rerun.selected_output_message.variant_index
    assert_equal turn.selected_input_message, rerun.selected_output_message.source_input_message
  end

  test "auto branches before rerunning a non tail finished output and uses the target output lineage" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    historical_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Historical input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    historical_output = attach_selected_output!(historical_turn, content: "Historical output")
    edited_turn = Turns::EditTailInput.call(turn: historical_turn, content: "Historical input revised")
    revised_output = AgentMessage.create!(
      installation: edited_turn.installation,
      conversation: edited_turn.conversation,
      turn: edited_turn,
      role: "agent",
      slot: "output",
      variant_index: 1,
      content: "Historical revised output",
      source_input_message: edited_turn.selected_input_message
    )
    edited_turn.update!(
      selected_output_message: revised_output,
      lifecycle_state: "completed"
    )
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    rerun_turn = Turns::RerunOutput.call(
      message: historical_output,
      content: "Branch rerun output"
    )

    assert rerun_turn.conversation.branch?
    assert_equal conversation, rerun_turn.conversation.parent_conversation
    assert_equal "Historical input", rerun_turn.selected_input_message.content
    assert_equal "Branch rerun output", rerun_turn.selected_output_message.content
    assert_equal rerun_turn.selected_input_message, rerun_turn.selected_output_message.source_input_message
  end

  test "rejects rerunning output from an archived conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output = attach_selected_output!(turn, content: "Archived output")
    turn.update!(lifecycle_state: "completed")
    conversation.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::RerunOutput.call(
        message: output,
        content: "Should not rerun"
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must belong to an active conversation to rewrite output"
  end

  test "rejects in place rerun when the target output is missing source input provenance" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    ),
      content: "Input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output = attach_selected_output!(turn, content: "Original output")
    turn.update!(lifecycle_state: "completed")
    output.update_columns(source_input_message_id: nil)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::RerunOutput.call(
        message: output.reload,
        content: "Should fail"
      )
    end

    assert_includes error.record.errors[:selected_output_message], "must carry source input provenance"
  end

  test "rejects branch rerun when the target output is missing source input provenance" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    historical_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Historical input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    historical_output = attach_selected_output!(historical_turn, content: "Historical output")
    historical_turn.update!(lifecycle_state: "completed")
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    historical_output.update_columns(source_input_message_id: nil)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::RerunOutput.call(
        message: historical_output.reload,
        content: "Should fail"
      )
    end

    assert_includes error.record.errors[:selected_output_message], "must carry source input provenance"
  end
end
