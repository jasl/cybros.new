require "test_helper"

class ConversationSummarySegmentTest < ActiveSupport::TestCase
  test "tracks replacement and supersession across transcript ranges" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    first_message = first_turn.selected_input_message
    second_message = second_turn.selected_input_message

    original = ConversationSummarySegment.create!(
      installation: conversation.installation,
      conversation: conversation,
      start_message: first_message,
      end_message: first_message,
      content: "Original summary"
    )
    replacement = ConversationSummarySegment.create!(
      installation: conversation.installation,
      conversation: conversation,
      start_message: first_message,
      end_message: second_message,
      content: "Replacement summary"
    )
    original.update!(superseded_by: replacement)

    assert_equal replacement, original.reload.superseded_by
    assert_nil replacement.superseded_by
  end

  test "does not validate transcript ordering in the model layer" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    invalid = ConversationSummarySegment.new(
      installation: conversation.installation,
      conversation: conversation,
      start_message: second_turn.selected_input_message,
      end_message: first_turn.selected_input_message,
      content: "Invalid summary"
    )

    assert_predicate invalid, :valid?
  end
end
