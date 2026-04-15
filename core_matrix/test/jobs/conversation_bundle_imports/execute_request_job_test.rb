require "test_helper"

class ConversationBundleImports::ExecuteRequestJobTest < ActiveSupport::TestCase
  test "executes a queued import request by public id" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Import job input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Import job output")
    bundle = ConversationExports::WriteZipBundle.call(conversation: conversation)
    request = ConversationBundleImportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      user: context[:user],
      lifecycle_state: "queued",
      request_payload: {
        "target_agent_definition_version_id" => context[:agent_definition_version].public_id,
        "target_workspace_agent_id" => context[:workspace_agent].public_id,
      }
    )
    request.upload_file.attach(
      io: StringIO.new(bundle.fetch("io").read),
      filename: bundle.fetch("filename"),
      content_type: bundle.fetch("content_type")
    )
    request.save!

    ConversationBundleImports::ExecuteRequestJob.perform_now(request.public_id)

    assert_predicate request.reload, :succeeded?
    assert request.imported_conversation.present?
  ensure
    bundle&.fetch("io")&.close!
  end
end
