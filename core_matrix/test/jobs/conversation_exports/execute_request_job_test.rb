require "test_helper"

class ConversationExports::ExecuteRequestJobTest < ActiveSupport::TestCase
  test "executes a queued export request by public id" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Job input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Job output")
    request = ConversationExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => "conversation_export" }
    )

    ConversationExports::ExecuteRequestJob.perform_now(request.public_id)

    assert_predicate request.reload, :succeeded?
    assert request.bundle_file.attached?
  end
end
