require "test_helper"

class ConversationBundleImportsParseUploadTest < ActiveSupport::TestCase
  test "parses a conversation export bundle into manifest payload and file bytes" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Importable input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_message_attachment!(
      message: turn.selected_input_message,
      filename: "input.txt",
      body: "attached input"
    )
    attach_selected_output!(turn, content: "Importable output")
    bundle = ConversationExports::WriteZipBundle.call(conversation: conversation)
    request = ConversationBundleImportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      user: context[:user],
      lifecycle_state: "queued",
      request_payload: {
        "target_agent_definition_version_id" => context[:agent_definition_version].public_id,
      }
    )
    request.upload_file.attach(
      io: StringIO.new(bundle.fetch("io").read),
      filename: bundle.fetch("filename"),
      content_type: bundle.fetch("content_type")
    )
    request.save!

    parsed_bundle = ConversationBundleImports::ParseUpload.call(request: request)

    assert_equal "conversation_export", parsed_bundle.dig("manifest", "bundle_kind")
    assert_equal "2026-04-02", parsed_bundle.dig("manifest", "bundle_version")
    assert_equal 2, parsed_bundle.dig("conversation_payload", "messages").length
    assert_equal 1, parsed_bundle.fetch("file_bytes").length
  ensure
    bundle&.fetch("io")&.close!
  end
end
