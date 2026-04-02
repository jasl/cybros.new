require "test_helper"

class AppApiConversationExportRequestsTest < ActionDispatch::IntegrationTest
  test "create and show expose queued export requests and enqueue execution" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    assert_enqueued_with(job: ConversationExports::ExecuteRequestJob) do
      assert_enqueued_with(job: ConversationExports::ExpireRequestJob) do
        post "/app_api/conversation_export_requests",
          params: {
            conversation_id: context[:conversation].public_id,
          },
          headers: app_api_headers(registration[:machine_credential]),
          as: :json
      end
    end

    assert_response :created
    response_body = JSON.parse(response.body)
    request_id = response_body.dig("export_request", "request_id")

    assert_equal "conversation_export_request_create", response_body.fetch("method_id")
    assert_equal context[:conversation].public_id, response_body.fetch("conversation_id")
    assert_equal "queued", response_body.dig("export_request", "lifecycle_state")
    assert_equal context[:conversation].public_id, response_body.dig("export_request", "conversation_id")
    refute_includes response.body, %("#{context[:conversation].id}")

    get "/app_api/conversation_export_requests/#{request_id}",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "conversation_export_request_show", response_body.fetch("method_id")
    assert_equal request_id, response_body.dig("export_request", "request_id")
    assert_equal context[:conversation].public_id, response_body.dig("export_request", "conversation_id")
  end

  test "download streams the export bundle once the request succeeds" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    attach_selected_output!(context[:turn], content: "Export output")
    request = ConversationExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: context[:conversation],
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => "conversation_export" }
    )
    ConversationExports::ExecuteRequest.call(request: request)

    get "/app_api/conversation_export_requests/#{request.public_id}/download",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :success
    assert_equal "application/zip", response.media_type
    assert_includes response.headers["Content-Disposition"], ".zip"
    assert_predicate response.body.bytesize, :positive?
  end

  test "show and download treat past ttl bundles as unavailable even before expiry cleanup runs" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    attach_selected_output!(context[:turn], content: "Expired export output")
    request = ConversationExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: context[:conversation],
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 1.minute.ago,
      request_payload: { "bundle_kind" => "conversation_export" }
    )
    ConversationExports::ExecuteRequest.call(request: request)

    get "/app_api/conversation_export_requests/#{request.public_id}",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :success
    assert_equal false, JSON.parse(response.body).dig("export_request", "bundle_available")

    get "/app_api/conversation_export_requests/#{request.public_id}/download",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :gone
  end

  test "rejects raw bigint identifiers for create show and download" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    request = ConversationExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: context[:conversation],
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => "conversation_export" }
    )

    post "/app_api/conversation_export_requests",
      params: {
        conversation_id: context[:conversation].id,
      },
      headers: app_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :not_found

    get "/app_api/conversation_export_requests/#{request.id}",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :not_found

    get "/app_api/conversation_export_requests/#{request.id}/download",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :not_found
  end
end
