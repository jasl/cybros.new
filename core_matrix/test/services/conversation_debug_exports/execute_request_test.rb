require "test_helper"

class ConversationDebugExportsExecuteRequestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "executes a debug export request and attaches the bundle" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Debug execute input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Debug execute output")
    request = ConversationDebugExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => "conversation_debug_export" }
    )

    ConversationDebugExports::ExecuteRequest.call(request: request)

    assert_predicate request.reload, :succeeded?
    assert request.bundle_file.attached?
    assert_equal "conversation_debug_export", request.result_payload.fetch("bundle_kind")
  end

  test "re-enqueues expiration when the debug bundle finishes after its ttl" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Expired debug input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Expired debug output")
    request = ConversationDebugExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 1.minute.ago,
      request_payload: { "bundle_kind" => "conversation_debug_export" }
    )

    perform_enqueued_jobs only: ConversationDebugExports::ExpireRequestJob do
      ConversationDebugExports::ExecuteRequest.call(request: request)
    end

    assert_predicate request.reload, :expired?
    assert_not request.bundle_file.attached?
  end
end
