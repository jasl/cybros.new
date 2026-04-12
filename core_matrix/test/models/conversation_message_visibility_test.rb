require "test_helper"

class ConversationMessageVisibilityTest < ActiveSupport::TestCase
  test "tracks hidden and context exclusion overlays without mutating transcript rows" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    message = turn.selected_input_message

    overlay = ConversationMessageVisibility.create!(
      installation: conversation.installation,
      conversation: conversation,
      message: message,
      hidden: true,
      excluded_from_context: true
    )

    assert overlay.hidden?
    assert overlay.excluded_from_context?
    assert_equal message, overlay.message
    assert_equal conversation, overlay.conversation
    assert_equal "Original input", message.reload.content
  end

  test "requires one effective overlay state and a unique row per conversation message pair" do
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
    message = turn.selected_input_message

    ConversationMessageVisibility.create!(
      installation: conversation.installation,
      conversation: conversation,
      message: message,
      hidden: true
    )

    duplicate = ConversationMessageVisibility.new(
      installation: conversation.installation,
      conversation: conversation,
      message: message,
      excluded_from_context: true
    )
    inert = ConversationMessageVisibility.new(
      installation: conversation.installation,
      conversation: conversation,
      message: message
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:message_id], "has already been taken"
    assert_not inert.valid?
    assert_includes inert.errors[:base], "must hide the message or exclude it from context"
  end

  test "does not validate transcript membership in the model layer" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    foreign_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: foreign_conversation,
      content: "Input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    overlay = ConversationMessageVisibility.new(
      installation: conversation.installation,
      conversation: conversation,
      message: turn.selected_input_message,
      hidden: true
    )

    assert_predicate overlay, :valid?
  end
end
