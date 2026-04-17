require "test_helper"

class ExecutorApiAttachmentsControllerTest < ActionDispatch::IntegrationTest
  test "publish attaches a runtime-generated file to the selected output message" do
    context = build_agent_control_context!
    output_message = attach_selected_output!(context[:turn], content: "Built artifact ready")
    context[:turn].update!(lifecycle_state: "completed")
    upload = temp_upload(filename: "game-2048-dist.zip", body: "zip-bytes", content_type: "application/zip")

    assert_difference("MessageAttachment.count", 1) do
      post "/execution_runtime_api/attachments/publish",
        params: {
          turn_id: context[:turn].public_id,
          file: upload,
          publication_role: "primary_deliverable",
        },
        headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential])
    end

    assert_response :created

    attachment = output_message.reload.message_attachments.order(:id).last
    body = JSON.parse(response.body)

    assert_equal "publish_attachment", body.fetch("method_id")
    assert_equal context[:execution_runtime].public_id, body.fetch("execution_runtime_id")
    assert_equal context[:turn].public_id, body.fetch("turn_id")
    assert_equal context[:conversation].public_id, body.fetch("conversation_id")
    assert_equal attachment.public_id, body.dig("attachments", 0, "attachment_id")
    assert_equal "primary_deliverable", body.dig("attachments", 0, "publication_role")
    assert_equal "runtime_generated", body.dig("attachments", 0, "source_kind")
    assert_match %r{/rails/active_storage/blobs/redirect/}, body.dig("attachments", 0, "download_url")
  ensure
    upload&.tempfile&.close!
  end

  test "publish rejects turns whose conversation disallows artifact ingress" do
    context = build_agent_control_context!
    context[:conversation].update!(
      entry_policy_payload: context[:conversation].entry_policy_snapshot.merge("artifact_ingress" => false)
    )
    attach_selected_output!(context[:turn], content: "Built artifact ready")
    context[:turn].update!(lifecycle_state: "completed")
    upload = temp_upload(filename: "game-2048-dist.zip", body: "zip-bytes", content_type: "application/zip")

    assert_no_difference("MessageAttachment.count") do
      post "/execution_runtime_api/attachments/publish",
        params: {
          turn_id: context[:turn].public_id,
          file: upload,
          publication_role: "primary_deliverable",
        },
        headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential])
    end

    assert_response :unprocessable_entity
    assert_equal "publish_attachment_rejected", JSON.parse(response.body).fetch("method_id")
    assert_equal "artifact_ingress_not_allowed", JSON.parse(response.body).fetch("error")
  ensure
    upload&.tempfile&.close!
  end

  test "publish rejects turns without a selected output message" do
    context = build_agent_control_context!
    upload = temp_upload(filename: "game-2048-dist.zip", body: "zip-bytes", content_type: "application/zip")

    assert_no_difference("MessageAttachment.count") do
      post "/execution_runtime_api/attachments/publish",
        params: {
          turn_id: context[:turn].public_id,
          file: upload,
          publication_role: "primary_deliverable",
        },
        headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential])
    end

    assert_response :unprocessable_entity
    assert_equal "publish_attachment_rejected", JSON.parse(response.body).fetch("method_id")
    assert_equal "selected_output_message_missing", JSON.parse(response.body).fetch("error")
  ensure
    upload&.tempfile&.close!
  end

  test "publish rejects turns that are not completed" do
    context = build_agent_control_context!
    attach_selected_output!(context[:turn], content: "Built artifact ready")
    upload = temp_upload(filename: "game-2048-dist.zip", body: "zip-bytes", content_type: "application/zip")

    assert_no_difference("MessageAttachment.count") do
      post "/execution_runtime_api/attachments/publish",
        params: {
          turn_id: context[:turn].public_id,
          file: upload,
          publication_role: "primary_deliverable",
        },
        headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential])
    end

    assert_response :unprocessable_entity
    assert_equal "publish_attachment_rejected", JSON.parse(response.body).fetch("method_id")
    assert_equal "turn_not_completed", JSON.parse(response.body).fetch("error")
  ensure
    upload&.tempfile&.close!
  end

  test "publish rejects a runtime-generated attachment without publication_role" do
    context = build_agent_control_context!
    attach_selected_output!(context[:turn], content: "Built artifact ready")
    context[:turn].update!(lifecycle_state: "completed")
    upload = temp_upload(filename: "game-2048-dist.zip", body: "zip-bytes", content_type: "application/zip")

    assert_no_difference("MessageAttachment.count") do
      post "/execution_runtime_api/attachments/publish",
        params: {
          turn_id: context[:turn].public_id,
          file: upload,
        },
        headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential])
    end

    assert_response :unprocessable_entity
    assert_equal "publish_attachment_rejected", JSON.parse(response.body).fetch("method_id")
    assert_equal "publication_role_required", JSON.parse(response.body).fetch("error")
  ensure
    upload&.tempfile&.close!
  end

  test "publish rejects a runtime-generated attachment without any file payload" do
    context = build_agent_control_context!
    attach_selected_output!(context[:turn], content: "Built artifact ready")
    context[:turn].update!(lifecycle_state: "completed")

    assert_no_difference("MessageAttachment.count") do
      post "/execution_runtime_api/attachments/publish",
        params: {
          turn_id: context[:turn].public_id,
          publication_role: "primary_deliverable",
        },
        headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
        as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "publish_attachment_rejected", JSON.parse(response.body).fetch("method_id")
    assert_equal "files_missing", JSON.parse(response.body).fetch("error")
  end

  test "refresh_attachment returns a signed handle for an attachment on the turn snapshot" do
    context = build_agent_control_context!
    attachment = create_message_attachment!(
      message: context[:turn].selected_input_message,
      filename: "notes.txt",
      body: "hello attachment"
    )
    attachment.file.blob.update!(
      metadata: attachment.file.blob.metadata.merge(
        "publication_role" => "evidence",
        "source_kind" => "app_upload"
      )
    )
    Workflows::BuildExecutionSnapshot.call(turn: context[:turn])

    post "/execution_runtime_api/attachments/request",
      params: {
        turn_id: context[:turn].public_id,
        attachment_id: attachment.public_id,
      },
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :success

    body = JSON.parse(response.body)
    attachment_payload = body.fetch("attachment")

    assert_equal "refresh_attachment", body.fetch("method_id")
    assert_equal context[:execution_runtime].public_id, body.fetch("execution_runtime_id")
    assert_equal context[:turn].public_id, body.fetch("turn_id")
    assert_equal context[:conversation].public_id, body.fetch("conversation_id")
    assert_equal attachment.public_id, attachment_payload.fetch("attachment_id")
    assert_equal "notes.txt", attachment_payload.fetch("filename")
    assert_equal "evidence", attachment_payload.fetch("publication_role")
    assert_equal "app_upload", attachment_payload.fetch("source_kind")
    assert attachment_payload.fetch("blob_signed_id").present?
    assert_match %r{/rails/active_storage/blobs/redirect/}, attachment_payload.fetch("download_url")
  end

  test "refresh_attachment rejects an execution runtime connection from another runtime" do
    context = build_agent_control_context!
    attachment = create_message_attachment!(message: context[:turn].selected_input_message)
    Workflows::BuildExecutionSnapshot.call(turn: context[:turn])

    other_registration = register_agent_runtime!(
      installation: context[:installation],
      actor: context[:actor],
      agent: create_agent!(installation: context[:installation]),
      execution_runtime: create_execution_runtime!(installation: context[:installation])
    )

    post "/execution_runtime_api/attachments/request",
      params: {
        turn_id: context[:turn].public_id,
        attachment_id: attachment.public_id,
      },
      headers: execution_runtime_api_headers(other_registration.fetch(:execution_runtime_connection_credential)),
      as: :json

    assert_response :not_found
  end

  test "publish rejects an execution runtime connection from another runtime" do
    context = build_agent_control_context!
    attach_selected_output!(context[:turn], content: "Built artifact ready")
    context[:turn].update!(lifecycle_state: "completed")
    upload = temp_upload(filename: "game-2048-dist.zip", body: "zip-bytes", content_type: "application/zip")

    other_registration = register_agent_runtime!(
      installation: context[:installation],
      actor: context[:actor],
      agent: create_agent!(installation: context[:installation]),
      execution_runtime: create_execution_runtime!(installation: context[:installation])
    )

    assert_no_difference("MessageAttachment.count") do
      post "/execution_runtime_api/attachments/publish",
        params: {
          turn_id: context[:turn].public_id,
          file: upload,
          publication_role: "primary_deliverable",
        },
        headers: execution_runtime_api_headers(other_registration.fetch(:execution_runtime_connection_credential))
    end

    assert_response :not_found
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
