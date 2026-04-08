require "test_helper"

class ConversationBundleImportRequestTest < ActiveSupport::TestCase
  test "generates a public id and requires an upload file" do
    context = create_workspace_context!

    request = ConversationBundleImportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      user: context[:user],
      lifecycle_state: "queued",
      request_payload: { "bundle_kind" => "conversation_export" }
    )

    assert_not request.valid?
    assert_includes request.errors[:upload_file], "must be attached"

    request.upload_file.attach(
      io: StringIO.new("zip payload"),
      filename: "conversation-export.zip",
      content_type: "application/zip"
    )

    assert request.valid?
    request.save!

    assert request.public_id.present?
    assert_equal request, ConversationBundleImportRequest.find_by_public_id!(request.public_id)
  end

  test "only allows queued running succeeded and failed states and keeps imported conversations in the same workspace" do
    context = create_workspace_context!
    imported_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    other_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      user_program_binding: context[:user_program_binding]
    )
    foreign_conversation = Conversations::CreateRoot.call(
      workspace: other_workspace,
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )

    unsupported_state = ConversationBundleImportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      user: context[:user],
      lifecycle_state: "expired",
      request_payload: {}
    )
    unsupported_state.upload_file.attach(
      io: StringIO.new("zip payload"),
      filename: "conversation-export.zip",
      content_type: "application/zip"
    )

    assert_not unsupported_state.valid?
    assert_includes unsupported_state.errors[:lifecycle_state], "is not included in the list"

    workspace_mismatch = ConversationBundleImportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      user: context[:user],
      imported_conversation: foreign_conversation,
      lifecycle_state: "succeeded",
      started_at: Time.current,
      finished_at: Time.current,
      request_payload: {},
      result_payload: { "conversation_public_id" => imported_conversation.public_id }
    )
    workspace_mismatch.upload_file.attach(
      io: StringIO.new("zip payload"),
      filename: "conversation-export.zip",
      content_type: "application/zip"
    )

    assert_not workspace_mismatch.valid?
    assert_includes workspace_mismatch.errors[:imported_conversation], "must belong to the same workspace"
  end
end
