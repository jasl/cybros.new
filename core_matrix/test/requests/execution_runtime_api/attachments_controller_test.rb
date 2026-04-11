require "test_helper"

class ExecutorApiAttachmentsControllerTest < ActionDispatch::IntegrationTest
  test "request_attachment returns a signed handle for an attachment on the turn snapshot" do
    context = build_agent_control_context!
    attachment = create_message_attachment!(
      message: context[:turn].selected_input_message,
      filename: "notes.txt",
      body: "hello attachment"
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

    assert_equal "request_attachment", body.fetch("method_id")
    assert_equal context[:execution_runtime].public_id, body.fetch("execution_runtime_id")
    assert_equal context[:turn].public_id, body.fetch("turn_id")
    assert_equal context[:conversation].public_id, body.fetch("conversation_id")
    assert_equal attachment.public_id, attachment_payload.fetch("attachment_id")
    assert_equal "notes.txt", attachment_payload.fetch("filename")
    assert attachment_payload.fetch("blob_signed_id").present?
    assert_match %r{/rails/active_storage/blobs/redirect/}, attachment_payload.fetch("download_url")
  end

  test "request_attachment rejects an execution runtime connection from another runtime" do
    context = build_agent_control_context!
    attachment = create_message_attachment!(message: context[:turn].selected_input_message)
    Workflows::BuildExecutionSnapshot.call(turn: context[:turn])

    other_registration = register_agent_runtime!(
      installation: context[:installation],
      actor: context[:actor],
      agent: create_agent!(installation: context[:installation]),
      execution_runtime: create_execution_runtime!(installation: context[:installation]),
      reuse_enrollment: true
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
end
