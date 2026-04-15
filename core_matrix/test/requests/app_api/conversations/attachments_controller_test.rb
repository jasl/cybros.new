require "test_helper"

class AppApiConversationsAttachmentsControllerTest < ActionDispatch::IntegrationTest
  test "uploads an attachment into a conversation message and returns discoverable metadata" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Need an attachment",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    upload = temp_upload(filename: "report.txt", body: "artifact body", content_type: "text/plain")

    assert_difference("MessageAttachment.count", 1) do
      post "/app_api/conversations/#{conversation.public_id}/attachments",
        params: {
          message_id: turn.selected_input_message.public_id,
          files: [upload],
          publication_role: "evidence"
        },
        headers: app_api_headers(session.plaintext_token)
    end

    assert_response :created
    attachment = MessageAttachment.order(:id).last

    assert_equal "conversation_attachment_create", response.parsed_body.fetch("method_id")
    assert_equal conversation.public_id, response.parsed_body.fetch("conversation_id")
    assert_equal attachment.public_id, response.parsed_body.dig("attachments", 0, "attachment_id")
    assert_equal "evidence", response.parsed_body.dig("attachments", 0, "publication_role")

    get "/app_api/conversations/#{conversation.public_id}/attachments/#{attachment.public_id}",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal "conversation_attachment_show", response.parsed_body.fetch("method_id")
    assert_equal attachment.public_id, response.parsed_body.dig("attachment", "attachment_id")
    assert_match %r{/rails/active_storage/blobs/redirect/}, response.parsed_body.dig("attachment", "download_url")
  ensure
    upload&.tempfile&.close!
  end

  test "rejects raw bigint identifiers for message and attachment lookups" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Need an attachment",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attachment = create_message_attachment!(message: turn.selected_input_message)
    upload = temp_upload(filename: "report.txt", body: "artifact body", content_type: "text/plain")

    post "/app_api/conversations/#{conversation.public_id}/attachments",
      params: {
        message_id: turn.selected_input_message.id,
        files: [upload]
      },
      headers: app_api_headers(session.plaintext_token)

    assert_response :not_found

    get "/app_api/conversations/#{conversation.public_id}/attachments/#{attachment.id}",
      headers: app_api_headers(session.plaintext_token)

    assert_response :not_found
  ensure
    upload&.tempfile&.close!
  end

  test "rejects unsupported publication roles as a controlled client error" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Need an attachment",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    upload = temp_upload(filename: "report.txt", body: "artifact body", content_type: "text/plain")

    assert_no_difference("MessageAttachment.count") do
      post "/app_api/conversations/#{conversation.public_id}/attachments",
        params: {
          message_id: turn.selected_input_message.public_id,
          files: [upload],
          publication_role: "not_a_role"
        },
        headers: app_api_headers(session.plaintext_token)
    end

    assert_response :unprocessable_entity
    assert_equal "conversation_attachment_rejected", response.parsed_body.fetch("method_id")
    assert_equal "invalid_publication_role", response.parsed_body.fetch("rejection_reason")
  ensure
    upload&.tempfile&.close!
  end

  private

  def temp_upload(filename:, body:, content_type:)
    tempfile = Tempfile.new([File.basename(filename, ".*"), File.extname(filename)])
    tempfile.write(body)
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, content_type, true, original_filename: filename)
  end
end
