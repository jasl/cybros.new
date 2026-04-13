require "test_helper"

class AppApiConversationSupervisionMessagesTest < ActionDispatch::IntegrationTest
  include ConversationSupervisionFixtureBuilder

  test "posting a message persists a snapshot-backed exchange and listing returns session history only" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)
    transcript_count = fixture.fetch(:conversation).messages.count

    post "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.public_id}/messages",
      params: {
        content: "What changed most recently?",
      },
      headers: app_api_headers(registration[:session_token]),
      as: :json

    assert_response :created
    assert_equal transcript_count, fixture.fetch(:conversation).reload.messages.count

    response_body = JSON.parse(response.body)
    assert_equal "conversation_supervision_message_create", response_body.fetch("method_id")
    assert_equal session.public_id, response_body.fetch("supervision_session_id")
    assert_equal "waiting", response_body.dig("machine_status", "overall_state")
    assert_match(/most recently|latest/i, response_body.dig("human_sidechat", "content"))
    refute_match(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/, response_body.dig("human_sidechat", "content"))
    refute_match(/\bprovider_round|tool_|runtime\.workflow_node|subagent_barrier\b/, response_body.dig("human_sidechat", "content"))
    assert_equal "user", response_body.dig("user_message", "role")
    assert_equal "supervisor_agent", response_body.dig("supervisor_message", "role")

    get "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.public_id}/messages",
      headers: app_api_headers(registration[:session_token])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_supervision_message_list", response_body.fetch("method_id")
    assert_equal session.public_id, response_body.fetch("supervision_session_id")
    assert_equal %w[user supervisor_agent], response_body.fetch("items").map { |item| item.fetch("role") }
    assert_equal "What changed most recently?", response_body.fetch("items").first.fetch("content")
  end

  test "rejects raw bigint session identifiers for create and list" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)

    post "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.id}/messages",
      params: {
        content: "What changed most recently?",
      },
      headers: app_api_headers(registration[:session_token]),
      as: :json

    assert_response :not_found

    get "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.id}/messages",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found
  end

  test "treats closed supervision sessions as gone" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)
    session.update!(lifecycle_state: "closed")

    get "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.public_id}/messages",
      headers: app_api_headers(registration[:session_token])

    assert_response :gone

    post "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.public_id}/messages",
      params: {
        content: "What changed most recently?",
      },
      headers: app_api_headers(registration[:session_token]),
      as: :json

    assert_response :gone
  end

  test "returns bounded control confirmation for high-confidence control phrases" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)

    assert_difference("ConversationControlRequest.count", 1) do
      post "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.public_id}/messages",
        params: {
          content: "快住手",
        },
        headers: app_api_headers(registration[:session_token]),
        as: :json
    end

    assert_response :created

    response_body = JSON.parse(response.body)

    assert_equal "control_request", response_body.dig("human_sidechat", "intent")
    assert_equal "request_turn_interrupt", response_body.dig("human_sidechat", "classified_intent")
    assert_equal "control_dispatched", response_body.dig("human_sidechat", "response_kind")
    assert_match(/stop|interrupt/i, response_body.dig("human_sidechat", "content"))
  end

  test "returns not found when session messages are requested through the wrong conversation scope" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)
    other_conversation = create_conversation_record!(
      workspace: fixture[:workspace],
      agent_definition_version: fixture[:agent_definition_version],
      execution_runtime: fixture[:execution_runtime]
    )

    get "/app_api/conversations/#{other_conversation.public_id}/supervision_sessions/#{session.public_id}/messages",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found

    post "/app_api/conversations/#{other_conversation.public_id}/supervision_sessions/#{session.public_id}/messages",
      params: {
        content: "What changed most recently?",
      },
      headers: app_api_headers(registration[:session_token]),
      as: :json

    assert_response :not_found
  end

  test "lists supervision session messages within seven SQL queries" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)
    EmbeddedAgents::ConversationSupervision::AppendMessage.call(
      actor: fixture[:user],
      conversation_supervision_session: session,
      content: "What changed most recently?"
    )

    assert_sql_query_count_at_most(7) do
      get "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.public_id}/messages",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success
  end
end
