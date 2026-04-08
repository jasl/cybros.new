require "test_helper"

class ConversationDebugExports::ExpireRequestJobTest < ActiveSupport::TestCase
  test "expires a completed debug export request and purges the bundle file" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Debug expire input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Debug expire output")
    request = ConversationDebugExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 1.minute.ago,
      request_payload: { "bundle_kind" => "conversation_debug_export" }
    )
    ConversationDebugExports::ExecuteRequest.call(request: request)

    assert_predicate request.reload, :succeeded?
    assert request.bundle_file.attached?

    ConversationDebugExports::ExpireRequestJob.perform_now(request.public_id)

    assert_predicate request.reload, :expired?
    assert_not request.bundle_file.attached?
  end

  test "does not rewrite failed debug export requests to expired" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    request = ConversationDebugExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "failed",
      expires_at: 1.minute.ago,
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      request_payload: { "bundle_kind" => "conversation_debug_export" },
      failure_payload: { "message" => "boom" }
    )

    ConversationDebugExports::ExpireRequestJob.perform_now(request.public_id)

    assert_predicate request.reload, :failed?
  end
end
