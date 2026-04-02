require "test_helper"

class ConversationBundleImportsValidateManifestTest < ActiveSupport::TestCase
  test "accepts a valid exported bundle and rejects unsupported bundle kinds and metadata mismatches" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Validation input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_message_attachment!(
      message: turn.selected_input_message,
      filename: "input.txt",
      body: "validate me"
    )
    attach_selected_output!(turn, content: "Validation output")
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

    assert ConversationBundleImports::ValidateManifest.call(parsed_bundle: parsed_bundle)

    parsed_bundle["manifest"]["bundle_kind"] = "third_party_export"

    assert_raises(ConversationBundleImports::ValidateManifest::InvalidBundle) do
      ConversationBundleImports::ValidateManifest.call(parsed_bundle: parsed_bundle)
    end

    parsed_bundle["manifest"]["bundle_kind"] = "conversation_export"
    parsed_bundle["manifest"]["files"].first["filename"] = "tampered.txt"

    assert_raises(ConversationBundleImports::ValidateManifest::InvalidBundle) do
      ConversationBundleImports::ValidateManifest.call(parsed_bundle: parsed_bundle)
    end

    parsed_bundle = ConversationBundleImports::ParseUpload.call(request: request)
    parsed_bundle["manifest"]["checksums"] = {}

    assert_raises(ConversationBundleImports::ValidateManifest::InvalidBundle) do
      ConversationBundleImports::ValidateManifest.call(parsed_bundle: parsed_bundle)
    end

    parsed_bundle = ConversationBundleImports::ParseUpload.call(request: request)
    parsed_bundle["entries"].delete("transcript.md")

    assert_raises(ConversationBundleImports::ValidateManifest::InvalidBundle) do
      ConversationBundleImports::ValidateManifest.call(parsed_bundle: parsed_bundle)
    end
  ensure
    bundle&.fetch("io")&.close!
  end
end
