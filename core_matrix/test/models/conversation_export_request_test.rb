require "test_helper"

class ConversationExportRequestTest < ActiveSupport::TestCase
  test "generates a public id and requires expires at" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )

    request = ConversationExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => "conversation_export" }
    )

    assert request.public_id.present?
    assert_equal request, ConversationExportRequest.find_by_public_id!(request.public_id)

    missing_expiry = ConversationExportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "queued",
      request_payload: {}
    )

    assert_not missing_expiry.valid?
    assert_includes missing_expiry.errors[:expires_at], "can't be blank"
  end

  test "requires succeeded requests to have a bundle file and matching workspace ownership" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    other_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      user_agent_binding: context[:user_agent_binding]
    )

    workspace_mismatch = ConversationExportRequest.new(
      installation: context[:installation],
      workspace: other_workspace,
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: {}
    )

    assert_not workspace_mismatch.valid?
    assert_includes workspace_mismatch.errors[:conversation], "must belong to the same workspace"

    succeeded_without_bundle = ConversationExportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "succeeded",
      expires_at: 2.hours.from_now,
      started_at: Time.current,
      finished_at: Time.current,
      request_payload: {},
      result_payload: { "message_count" => 1 }
    )

    assert_not succeeded_without_bundle.valid?
    assert_includes succeeded_without_bundle.errors[:bundle_file], "must be attached once the export succeeds"

    succeeded_with_bundle = ConversationExportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "succeeded",
      expires_at: 2.hours.from_now,
      started_at: Time.current,
      finished_at: Time.current,
      request_payload: {},
      result_payload: { "message_count" => 1 }
    )
    succeeded_with_bundle.bundle_file.attach(
      io: StringIO.new("zip payload"),
      filename: "conversation-export.zip",
      content_type: "application/zip"
    )

    assert succeeded_with_bundle.valid?
  end
end
