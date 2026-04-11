require "test_helper"

class Turns::SelectOutputVariantTest < ActiveSupport::TestCase
  test "selects a finished tail output variant and restores the matching input lineage" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    ),
      content: "Input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    first_output = attach_selected_output!(turn, content: "Output one")
    edited_turn = Turns::EditTailInput.call(turn: turn, content: "Revised input")
    revised_input = edited_turn.selected_input_message
    second_output = AgentMessage.create!(
      installation: edited_turn.installation,
      conversation: edited_turn.conversation,
      turn: edited_turn,
      role: "agent",
      slot: "output",
      variant_index: 1,
      content: "Output two",
      source_input_message: revised_input
    )
    edited_turn.update!(
      selected_output_message: second_output,
      lifecycle_state: "completed"
    )

    selected = Turns::SelectOutputVariant.call(message: second_output)

    assert_equal turn.id, selected.id
    assert_equal second_output, selected.selected_output_message
    assert_equal revised_input, selected.selected_input_message
    assert_equal revised_input, second_output.source_input_message

    restored = Turns::SelectOutputVariant.call(message: first_output)

    assert_equal first_output, restored.selected_output_message
    assert_equal turn.messages.where(slot: "input", variant_index: 0).first, restored.selected_input_message
  end

  test "rejects selecting a non tail output variant in the current timeline" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    historical_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Historical input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    first_output = attach_selected_output!(historical_turn, content: "Historical output")
    historical_turn.update!(lifecycle_state: "completed")
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Turns::SelectOutputVariant.call(message: first_output)
    end
  end

  test "rejects selecting an output variant while close is in progress" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Output one")
    second_output = AgentMessage.create!(
      installation: turn.installation,
      conversation: turn.conversation,
      turn: turn,
      role: "agent",
      slot: "output",
      variant_index: 1,
      content: "Output two",
      source_input_message: turn.selected_input_message
    )
    turn.update!(lifecycle_state: "completed")
    ConversationCloseOperation.create!(
      installation: conversation.installation,
      conversation: conversation,
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::SelectOutputVariant.call(message: second_output)
    end

    assert_includes error.record.errors[:base], "must not select an output variant while close is in progress"
  end
end
