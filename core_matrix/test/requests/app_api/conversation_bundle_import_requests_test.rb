require "test_helper"

class AppApiConversationBundleImportRequestsTest < ActionDispatch::IntegrationTest
  test "create and show expose queued import requests and enqueue execution" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    bundle = ConversationExports::WriteZipBundle.call(conversation: context[:conversation])
    upload = Rack::Test::UploadedFile.new(bundle.fetch("io").path, bundle.fetch("content_type"), true)

    assert_enqueued_with(job: ConversationBundleImports::ExecuteRequestJob) do
      post "/app_api/conversation_bundle_import_requests",
        params: {
          workspace_id: context[:workspace].public_id,
          upload_file: upload,
        },
        headers: app_api_headers(registration[:machine_credential])
    end

    assert_response :created
    response_body = JSON.parse(response.body)
    request_id = response_body.dig("import_request", "request_id")

    assert_equal "conversation_bundle_import_request_create", response_body.fetch("method_id")
    assert_equal context[:workspace].public_id, response_body.fetch("workspace_id")
    assert_equal "queued", response_body.dig("import_request", "lifecycle_state")
    assert_equal context[:workspace].public_id, response_body.dig("import_request", "workspace_id")
    refute_includes response.body, %("#{context[:workspace].id}")

    get "/app_api/conversation_bundle_import_requests/#{request_id}",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "conversation_bundle_import_request_show", response_body.fetch("method_id")
    assert_equal request_id, response_body.dig("import_request", "request_id")
    assert_equal context[:workspace].public_id, response_body.dig("import_request", "workspace_id")
  ensure
    bundle&.fetch("io")&.close!
  end

  test "rejects raw bigint identifiers for create and show" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    bundle = ConversationExports::WriteZipBundle.call(conversation: context[:conversation])
    upload = Rack::Test::UploadedFile.new(bundle.fetch("io").path, bundle.fetch("content_type"), true)
    request = ConversationBundleImportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      user: context[:user],
      lifecycle_state: "queued",
      request_payload: { "target_agent_program_version_id" => context[:agent_program_version].public_id }
    )
    request.upload_file.attach(
      io: StringIO.new(File.binread(bundle.fetch("io").path)),
      filename: bundle.fetch("filename"),
      content_type: bundle.fetch("content_type")
    )
    request.save!

    post "/app_api/conversation_bundle_import_requests",
      params: {
        workspace_id: context[:workspace].id,
        upload_file: upload,
      },
      headers: app_api_headers(registration[:machine_credential])

    assert_response :not_found

    get "/app_api/conversation_bundle_import_requests/#{request.id}",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :not_found
  ensure
    bundle&.fetch("io")&.close!
  end

  test "show falls back to result payload imported conversation id when the association is unavailable" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    imported_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    request = ConversationBundleImportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      user: context[:user],
      lifecycle_state: "succeeded",
      result_payload: {
        "bundle_kind" => "conversation_export",
        "bundle_version" => "2026-04-02",
        "imported_conversation_id" => imported_conversation.public_id,
      },
      imported_conversation: imported_conversation
    )
    request.upload_file.attach(
      io: StringIO.new("fake zip bytes"),
      filename: "conversation-import.zip",
      content_type: "application/zip"
    )
    request.save!

    request.update_columns(imported_conversation_id: nil)

    get "/app_api/conversation_bundle_import_requests/#{request.public_id}",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal imported_conversation.public_id, response_body.dig("import_request", "imported_conversation_id")
  end
end
