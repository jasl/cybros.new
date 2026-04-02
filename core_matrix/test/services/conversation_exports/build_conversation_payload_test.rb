require "test_helper"

class ConversationExportsBuildConversationPayloadTest < ActiveSupport::TestCase
  test "builds a public-id-only payload with message-bound attachments" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Export me",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_message_attachment!(
      message: turn.selected_input_message,
      filename: "input.txt",
      body: "input attachment"
    )
    output_message = attach_selected_output!(turn, content: "Here is the exported answer")
    create_message_attachment!(
      message: output_message,
      filename: "output.txt",
      body: "output attachment"
    )

    payload = ConversationExports::BuildConversationPayload.call(conversation: conversation)

    assert_equal "conversation_export", payload.fetch("bundle_kind")
    assert_equal "2026-04-02", payload.fetch("bundle_version")
    assert_equal conversation.public_id, payload.dig("conversation", "public_id")
    assert_equal 2, payload.fetch("messages").length

    input_message = payload.fetch("messages").find { |message| message.fetch("message_public_id") == turn.selected_input_message.public_id }
    output_payload = payload.fetch("messages").find { |message| message.fetch("message_public_id") == output_message.public_id }

    assert_equal "user", input_message.fetch("role")
    assert_equal "agent", output_payload.fetch("role")
    assert_equal "user_upload", input_message.fetch("attachments").first.fetch("kind")
    assert_equal "generated_output", output_payload.fetch("attachments").first.fetch("kind")
    assert_match(/\Afiles\//, input_message.fetch("attachments").first.fetch("relative_path"))
    assert_match(/\Afiles\//, output_payload.fetch("attachments").first.fetch("relative_path"))

    json = JSON.generate(payload)
    refute_includes json, %("#{conversation.id}")
    refute_includes json, %("#{turn.id}")
  end
end
