require "test_helper"

class ConversationDebugExportRequestTest < ActiveSupport::TestCase
  test "generates a public id and requires expires at" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )

    request = ConversationDebugExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => "conversation_debug_export" }
    )

    assert request.public_id.present?
    assert_equal request, ConversationDebugExportRequest.find_by_public_id!(request.public_id)
  end

  test "requires succeeded requests to have a bundle file and a matching installation" do
    context = create_workspace_context!
    foreign_user = context[:user].dup
    foreign_user.installation_id = -1
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )

    installation_mismatch = ConversationDebugExportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: foreign_user,
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: {}
    )

    assert_not installation_mismatch.valid?
    assert_includes installation_mismatch.errors[:user], "must belong to the same installation"

    succeeded_without_bundle = ConversationDebugExportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "succeeded",
      expires_at: 2.hours.from_now,
      started_at: Time.current,
      finished_at: Time.current,
      request_payload: {},
      result_payload: { "workflow_run_count" => 1 }
    )

    assert_not succeeded_without_bundle.valid?
    assert_includes succeeded_without_bundle.errors[:bundle_file], "must be attached once the export succeeds"
  end
end
