require "test_helper"

class ConversationExports::ExpireRequestJobTest < ActiveSupport::TestCase
  test "expires a completed export request and purges the bundle file" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Expire input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Expire output")
    request = ConversationExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 1.minute.ago,
      request_payload: { "bundle_kind" => "conversation_export" }
    )
    ConversationExports::ExecuteRequest.call(request: request)

    assert_predicate request.reload, :succeeded?
    assert request.bundle_file.attached?

    ConversationExports::ExpireRequestJob.perform_now(request.public_id)

    assert_predicate request.reload, :expired?
    assert_not request.bundle_file.attached?
  end

  test "does not rewrite failed export requests to expired" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    request = ConversationExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "failed",
      expires_at: 1.minute.ago,
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      request_payload: { "bundle_kind" => "conversation_export" },
      failure_payload: { "message" => "boom" }
    )

    ConversationExports::ExpireRequestJob.perform_now(request.public_id)

    assert_predicate request.reload, :failed?
  end

  test "expires a completed debug export request and purges the bundle file" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Debug expire input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Debug expire output")
    request = ConversationExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      request_kind: "debug_export",
      lifecycle_state: "queued",
      expires_at: 1.minute.ago,
      request_payload: { "bundle_kind" => "conversation_debug_export" }
    )
    ConversationExports::ExecuteRequest.call(request: request)

    assert_predicate request.reload, :succeeded?
    assert request.bundle_file.attached?

    ConversationExports::ExpireRequestJob.perform_now(request.public_id)

    assert_predicate request.reload, :expired?
    assert_not request.bundle_file.attached?
  end
end
