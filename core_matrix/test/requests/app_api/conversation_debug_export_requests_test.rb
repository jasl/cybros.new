require "test_helper"

class AppApiConversationDebugExportRequestsTest < ActionDispatch::IntegrationTest
  test "create and show expose queued debug export requests and enqueue execution and expiry" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    assert_enqueued_with(job: ConversationDebugExports::ExecuteRequestJob) do
      assert_enqueued_with(job: ConversationDebugExports::ExpireRequestJob) do
        post "/app_api/conversations/#{context[:conversation].public_id}/debug_export_requests",
          headers: app_api_headers(registration[:session_token]),
          as: :json
      end
    end

    assert_response :created
    response_body = JSON.parse(response.body)
    request_id = response_body.dig("debug_export_request", "request_id")

    assert_equal "conversation_debug_export_request_create", response_body.fetch("method_id")
    assert_equal context[:conversation].public_id, response_body.fetch("conversation_id")
    assert_equal "queued", response_body.dig("debug_export_request", "lifecycle_state")
    refute_includes response.body, %("#{context[:conversation].id}")

    get "/app_api/conversations/#{context[:conversation].public_id}/debug_export_requests/#{request_id}",
      headers: app_api_headers(registration[:session_token])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "conversation_debug_export_request_show", response_body.fetch("method_id")
    assert_equal request_id, response_body.dig("debug_export_request", "request_id")
  end

  test "download streams the debug export bundle once the request succeeds" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    attach_selected_output!(context[:turn], content: "Debug export output")
    request = ConversationDebugExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: context[:conversation],
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => "conversation_debug_export" }
    )
    ConversationDebugExports::ExecuteRequest.call(request: request)

    get "/app_api/conversations/#{context[:conversation].public_id}/debug_export_requests/#{request.public_id}/download",
      headers: app_api_headers(registration[:session_token])

    assert_response :success
    assert_equal "application/zip", response.media_type
    assert_includes response.headers["Content-Disposition"], ".zip"
    assert_predicate response.body.bytesize, :positive?
  end

  test "show and download treat missing succeeded debug bundles as unavailable" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    attach_selected_output!(context[:turn], content: "Missing debug export output")
    request = ConversationDebugExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: context[:conversation],
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => "conversation_debug_export" }
    )
    ConversationDebugExports::ExecuteRequest.call(request: request)
    request.bundle_file.purge

    get "/app_api/conversations/#{context[:conversation].public_id}/debug_export_requests/#{request.public_id}",
      headers: app_api_headers(registration[:session_token])

    assert_response :success
    assert_equal false, JSON.parse(response.body).dig("debug_export_request", "bundle_available")

    get "/app_api/conversations/#{context[:conversation].public_id}/debug_export_requests/#{request.public_id}/download",
      headers: app_api_headers(registration[:session_token])

    assert_response :gone
  end

  test "show and download treat past ttl debug bundles as unavailable even before expiry cleanup runs" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    attach_selected_output!(context[:turn], content: "Expired debug export output")
    request = ConversationDebugExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: context[:conversation],
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 1.minute.ago,
      request_payload: { "bundle_kind" => "conversation_debug_export" }
    )
    ConversationDebugExports::ExecuteRequest.call(request: request)

    get "/app_api/conversations/#{context[:conversation].public_id}/debug_export_requests/#{request.public_id}",
      headers: app_api_headers(registration[:session_token])

    assert_response :success
    assert_equal false, JSON.parse(response.body).dig("debug_export_request", "bundle_available")

    get "/app_api/conversations/#{context[:conversation].public_id}/debug_export_requests/#{request.public_id}/download",
      headers: app_api_headers(registration[:session_token])

    assert_response :gone
  end

  test "rejects raw bigint identifiers for create show and download" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    request = ConversationDebugExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: context[:conversation],
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => "conversation_debug_export" }
    )

    post "/app_api/conversations/#{context[:conversation].id}/debug_export_requests",
      headers: app_api_headers(registration[:session_token]),
      as: :json

    assert_response :not_found

    get "/app_api/conversations/#{context[:conversation].public_id}/debug_export_requests/#{request.id}",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found

    get "/app_api/conversations/#{context[:conversation].public_id}/debug_export_requests/#{request.id}/download",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found
  end

  test "show and download return not found through the wrong conversation scope" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    attach_selected_output!(context[:turn], content: "Scoped debug export output")
    request = ConversationDebugExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: context[:conversation],
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => "conversation_debug_export" }
    )
    ConversationDebugExports::ExecuteRequest.call(request: request)
    other_conversation = create_conversation_record!(
      workspace: context[:workspace],
      agent_definition_version: context[:agent_definition_version],
      execution_runtime: context[:execution_runtime]
    )

    get "/app_api/conversations/#{other_conversation.public_id}/debug_export_requests/#{request.public_id}",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found

    get "/app_api/conversations/#{other_conversation.public_id}/debug_export_requests/#{request.public_id}/download",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found
  end

  test "show loads a queued debug export request within six SQL queries" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    request = ConversationDebugExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: context[:conversation],
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => "conversation_debug_export" }
    )

    assert_sql_query_count_at_most(6) do
      get "/app_api/conversations/#{context[:conversation].public_id}/debug_export_requests/#{request.public_id}",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success
  end
end
