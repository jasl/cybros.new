require "test_helper"

class ConversationSummaries::CreateSegmentTest < ActiveSupport::TestCase
  test "creates a replacement segment and marks the previous segment superseded" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    first_message = first_turn.selected_input_message
    second_message = second_turn.selected_input_message
    original = ConversationSummaries::CreateSegment.call(
      conversation: conversation,
      start_message: first_message,
      end_message: first_message,
      content: "Initial summary"
    )

    replacement = ConversationSummaries::CreateSegment.call(
      conversation: conversation,
      start_message: first_message,
      end_message: second_message,
      content: "Expanded summary",
      supersedes: original
    )

    assert_equal replacement, original.reload.superseded_by
    assert_nil replacement.superseded_by
  end

  test "rejects ranges that run backward through the transcript projection" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      ConversationSummaries::CreateSegment.call(
        conversation: conversation,
        start_message: second_turn.selected_input_message,
        end_message: first_turn.selected_input_message,
        content: "Invalid summary"
      )
    end

    assert_includes error.record.errors[:end_message], "must come after the start message in transcript order"
  end
end
