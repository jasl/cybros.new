require "test_helper"

class AppApiConversationBundleImportRequestsTest < ActionDispatch::IntegrationTest
  test "create and show expose queued import requests and enqueue execution" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    bundle = ConversationExports::WriteZipBundle.call(conversation: context[:conversation])
    upload = Rack::Test::UploadedFile.new(bundle.fetch("io").path, bundle.fetch("content_type"), true)

    assert_enqueued_with(job: ConversationBundleImports::ExecuteRequestJob) do
      post "/app_api/workspaces/#{context[:workspace].public_id}/conversation_bundle_import_requests",
        params: {
          workspace_agent_id: context[:workspace_agent].public_id,
          upload_file: upload,
        },
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :created
    response_body = JSON.parse(response.body)
    request_id = response_body.dig("import_request", "request_id")

    assert_equal "conversation_bundle_import_request_create", response_body.fetch("method_id")
    assert_equal context[:workspace].public_id, response_body.fetch("workspace_id")
    assert_equal "queued", response_body.dig("import_request", "lifecycle_state")
    assert_equal context[:workspace].public_id, response_body.dig("import_request", "workspace_id")
    refute_includes response.body, %("#{context[:workspace].id}")
    assert_equal(
      registration[:agent_definition_version].public_id,
      ConversationBundleImportRequest.find_by_public_id!(request_id).request_payload.fetch("target_agent_definition_version_id")
    )
    assert_equal(
      context[:workspace_agent].public_id,
      ConversationBundleImportRequest.find_by_public_id!(request_id).request_payload.fetch("target_workspace_agent_id")
    )

    get "/app_api/workspaces/#{context[:workspace].public_id}/conversation_bundle_import_requests/#{request_id}",
      headers: app_api_headers(registration[:session_token])

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
      request_payload: { "target_agent_definition_version_id" => context[:agent_definition_version].public_id }
    )
    request.upload_file.attach(
      io: StringIO.new(File.binread(bundle.fetch("io").path)),
      filename: bundle.fetch("filename"),
      content_type: bundle.fetch("content_type")
    )
    request.save!

    post "/app_api/workspaces/#{context[:workspace].id}/conversation_bundle_import_requests",
      params: {
        workspace_agent_id: context[:workspace_agent].public_id,
        upload_file: upload,
      },
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found

    get "/app_api/workspaces/#{context[:workspace].public_id}/conversation_bundle_import_requests/#{request.id}",
      headers: app_api_headers(registration[:session_token])

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
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
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

    get "/app_api/workspaces/#{context[:workspace].public_id}/conversation_bundle_import_requests/#{request.public_id}",
      headers: app_api_headers(registration[:session_token])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal imported_conversation.public_id, response_body.dig("import_request", "imported_conversation_id")
  end

  test "create targets the requested workspace agent definition version" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    secondary_agent = create_agent!(installation: context[:installation], default_execution_runtime: context[:execution_runtime])
    secondary_agent_definition_version = create_agent_definition_version!(
      installation: context[:installation],
      agent: secondary_agent
    )
    secondary_agent.update!(
      current_agent_definition_version: secondary_agent_definition_version,
      published_agent_definition_version: secondary_agent_definition_version
    )
    secondary_workspace_agent = create_workspace_agent!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: secondary_agent,
      default_execution_runtime: context[:execution_runtime]
    )
    bundle = ConversationExports::WriteZipBundle.call(conversation: context[:conversation])
    upload = Rack::Test::UploadedFile.new(bundle.fetch("io").path, bundle.fetch("content_type"), true)

    post "/app_api/workspaces/#{context[:workspace].public_id}/conversation_bundle_import_requests",
      params: {
        workspace_agent_id: secondary_workspace_agent.public_id,
        upload_file: upload,
      },
      headers: app_api_headers(registration[:session_token])

    assert_response :created
    request_id = response.parsed_body.dig("import_request", "request_id")
    assert_equal(
      secondary_agent_definition_version.public_id,
      ConversationBundleImportRequest.find_by_public_id!(request_id).request_payload.fetch("target_agent_definition_version_id")
    )
    assert_equal(
      secondary_workspace_agent.public_id,
      ConversationBundleImportRequest.find_by_public_id!(request_id).request_payload.fetch("target_workspace_agent_id")
    )
  ensure
    bundle&.fetch("io")&.close!
  end

  test "create rejects a revoked workspace agent target" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    context[:workspace_agent].update!(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "owner_revoked"
    )
    bundle = ConversationExports::WriteZipBundle.call(conversation: context[:conversation])
    upload = Rack::Test::UploadedFile.new(bundle.fetch("io").path, bundle.fetch("content_type"), true)

    post "/app_api/workspaces/#{context[:workspace].public_id}/conversation_bundle_import_requests",
      params: {
        workspace_agent_id: context[:workspace_agent].public_id,
        upload_file: upload,
      },
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found
  ensure
    bundle&.fetch("io")&.close!
  end

  test "show returns not found through the wrong workspace scope" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    bundle = ConversationExports::WriteZipBundle.call(conversation: context[:conversation])
    request = ConversationBundleImportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      user: context[:user],
      lifecycle_state: "queued",
      request_payload: { "target_agent_definition_version_id" => context[:agent_definition_version].public_id }
    )
    request.upload_file.attach(
      io: StringIO.new(File.binread(bundle.fetch("io").path)),
      filename: bundle.fetch("filename"),
      content_type: bundle.fetch("content_type")
    )
    request.save!
    other_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      agent: context[:agent]
    )

    get "/app_api/workspaces/#{other_workspace.public_id}/conversation_bundle_import_requests/#{request.public_id}",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found
  ensure
    bundle&.fetch("io")&.close!
  end

  test "show loads a queued import request within six SQL queries" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    bundle = ConversationExports::WriteZipBundle.call(conversation: context[:conversation])
    request = ConversationBundleImportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      user: context[:user],
      lifecycle_state: "queued",
      request_payload: { "target_agent_definition_version_id" => context[:agent_definition_version].public_id }
    )
    request.upload_file.attach(
      io: StringIO.new(File.binread(bundle.fetch("io").path)),
      filename: bundle.fetch("filename"),
      content_type: bundle.fetch("content_type")
    )
    request.save!

    assert_sql_query_count_at_most(6) do
      get "/app_api/workspaces/#{context[:workspace].public_id}/conversation_bundle_import_requests/#{request.public_id}",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success
  ensure
    bundle&.fetch("io")&.close!
  end
end
