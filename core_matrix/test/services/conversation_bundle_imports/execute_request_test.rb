require "test_helper"

class ConversationBundleImportsExecuteRequestTest < ActiveSupport::TestCase
  test "imports a valid bundle into a new conversation and records the result" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Execute import question",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Execute import answer")
    bundle = ConversationExports::WriteZipBundle.call(conversation: conversation)
    request = ConversationBundleImportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      user: context[:user],
      lifecycle_state: "queued",
      request_payload: {
        "target_agent_program_version_id" => context[:agent_program_version].public_id,
      }
    )
    request.upload_file.attach(
      io: StringIO.new(bundle.fetch("io").read),
      filename: bundle.fetch("filename"),
      content_type: bundle.fetch("content_type")
    )
    request.save!

    ConversationBundleImports::ExecuteRequest.call(request: request)

    request.reload

    assert_predicate request, :succeeded?
    assert request.imported_conversation.present?
    assert_equal request.imported_conversation.public_id, request.result_payload.fetch("imported_conversation_id")
    assert_equal 2, request.result_payload.fetch("message_count")
  ensure
    bundle&.fetch("io")&.close!
  end
end
