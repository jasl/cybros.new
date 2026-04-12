require "test_helper"

class ConversationDebugExports::ExecuteRequestJobTest < ActiveSupport::TestCase
  test "executes a queued debug export request by public id" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Debug job input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Debug job output")
    request = ConversationDebugExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => "conversation_debug_export" }
    )

    ConversationDebugExports::ExecuteRequestJob.perform_now(request.public_id)

    assert_predicate request.reload, :succeeded?
    assert request.bundle_file.attached?
  end
end
