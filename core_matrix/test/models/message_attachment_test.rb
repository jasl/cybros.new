require "test_helper"

class MessageAttachmentTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attachment = create_message_attachment!(message: turn.selected_input_message)

    assert attachment.public_id.present?
    assert_equal attachment, MessageAttachment.find_by_public_id!(attachment.public_id)
  end

  test "requires an attached file and matching message ownership" do
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

    attachment = MessageAttachment.new(
      installation: conversation.installation,
      conversation: conversation,
      message: message
    )

    assert_not attachment.valid?
    assert_includes attachment.errors[:file], "can't be blank"

    attachment.file.attach(
      io: StringIO.new("hello"),
      filename: "hello.txt",
      content_type: "text/plain"
    )

    assert attachment.valid?
  end

  test "tracks attachment ancestry through origin attachment and message pointers" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    source_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Source input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    source_message = source_turn.selected_input_message
    source_attachment = create_message_attachment!(
      message: source_message,
      filename: "source.txt",
      body: "source attachment"
    )
    target_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Target input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    target_message = target_turn.selected_input_message
    materialized_attachment = create_message_attachment!(
      message: target_message,
      origin_attachment: source_attachment,
      filename: "source-copy.txt",
      body: "source attachment"
    )

    assert_equal source_attachment, materialized_attachment.origin_attachment
    assert_equal source_message, materialized_attachment.origin_message
    assert_equal target_message, materialized_attachment.message
    assert materialized_attachment.file.attached?
  end
end
