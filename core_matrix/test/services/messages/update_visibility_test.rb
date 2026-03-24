require "test_helper"

class Messages::UpdateVisibilityTest < ActiveSupport::TestCase
  test "creates and updates overlays without deleting immutable message rows" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    message = turn.selected_input_message

    overlay = Messages::UpdateVisibility.call(
      conversation: conversation,
      message: message,
      excluded_from_context: true
    )

    assert overlay.persisted?
    assert_not overlay.hidden?
    assert overlay.excluded_from_context?
    assert_equal [message.id], conversation.transcript_projection_messages.map(&:id)
    assert_empty conversation.context_projection_messages

    updated = Messages::UpdateVisibility.call(
      conversation: conversation,
      message: message,
      hidden: true
    )

    assert_equal overlay.id, updated.id
    assert updated.hidden?
    assert updated.excluded_from_context?
    assert_equal "Original input", message.reload.content
  end

  test "rejects messages outside the conversation transcript projection" do
    context = create_workspace_context!
    first_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    second_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: second_conversation,
      content: "Unrelated input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Messages::UpdateVisibility.call(
        conversation: first_conversation,
        message: turn.selected_input_message,
        hidden: true
      )
    end

    assert_includes error.record.errors[:message], "must be present in the conversation transcript projection"
  end
end
