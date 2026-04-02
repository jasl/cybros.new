require "test_helper"

class ConversationBundleImportsRehydrateConversationTest < ActiveSupport::TestCase
  test "creates a new conversation with preserved message order timestamps and attachments" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First importable question",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_message_attachment!(
      message: first_turn.selected_input_message,
      filename: "question.txt",
      body: "first attachment"
    )
    attach_selected_output!(first_turn, content: "First importable answer")
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second importable question",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(second_turn, content: "Second importable answer")
    bundle = ConversationExports::WriteZipBundle.call(conversation: conversation)
    request = ConversationBundleImportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      user: context[:user],
      lifecycle_state: "queued",
      request_payload: {
        "target_agent_deployment_id" => context[:agent_deployment].public_id,
      }
    )
    request.upload_file.attach(
      io: StringIO.new(bundle.fetch("io").read),
      filename: bundle.fetch("filename"),
      content_type: bundle.fetch("content_type")
    )
    request.save!

    parsed_bundle = ConversationBundleImports::ParseUpload.call(request: request)
    ConversationBundleImports::ValidateManifest.call(parsed_bundle: parsed_bundle)

    imported_conversation = ConversationBundleImports::RehydrateConversation.call(
      request: request,
      parsed_bundle: parsed_bundle
    )

    assert_not_equal conversation.public_id, imported_conversation.public_id
    assert_equal context[:workspace], imported_conversation.workspace
    assert_equal parsed_bundle.fetch("conversation_payload").fetch("messages").map { |message| message.fetch("content") },
      imported_conversation.messages.order(:created_at, :id).map(&:content)
    assert_equal parsed_bundle.fetch("conversation_payload").fetch("messages").map { |message| message.fetch("created_at") },
      imported_conversation.messages.order(:created_at, :id).map { |message| message.created_at.iso8601(6) }
    assert_equal 1, MessageAttachment.where(conversation: imported_conversation).count
  ensure
    bundle&.fetch("io")&.close!
  end
end
