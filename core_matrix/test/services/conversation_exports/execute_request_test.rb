require "test_helper"
require "zip"

class ConversationExportsExecuteRequestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    truncate_all_tables!
  end

  test "attaches the export bundle and records summary metadata on the request" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Execute input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_message_attachment!(
      message: turn.selected_input_message,
      filename: "input.txt",
      body: "attached"
    )
    attach_selected_output!(turn, content: "Execute output")
    request = ConversationExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => "conversation_export" }
    )

    ConversationExports::ExecuteRequest.call(request: request)

    request.reload

    assert_predicate request, :succeeded?
    assert request.started_at.present?
    assert request.finished_at.present?
    assert request.bundle_file.attached?
    assert_equal 2, request.result_payload.fetch("message_count")
    assert_equal 1, request.result_payload.fetch("attachment_count")

    Zip::File.open_buffer(StringIO.new(request.bundle_file.download)) do |zip_file|
      assert_includes zip_file.entries.map(&:name), "manifest.json"
      assert_includes zip_file.entries.map(&:name), "conversation.json"
    end
  end

  test "re-enqueues expiration when the bundle finishes after its ttl" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Expired export input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Expired export output")
    request = ConversationExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 1.minute.ago,
      request_payload: { "bundle_kind" => "conversation_export" }
    )

    perform_enqueued_jobs only: ConversationExports::ExpireRequestJob do
      ConversationExports::ExecuteRequest.call(request: request)
    end

    assert_predicate request.reload, :expired?
    assert_not request.bundle_file.attached?
  end
end
