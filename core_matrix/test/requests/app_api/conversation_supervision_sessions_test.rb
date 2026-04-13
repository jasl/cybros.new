require "test_helper"

class AppApiConversationSupervisionSessionsTest < ActionDispatch::IntegrationTest
  include ConversationSupervisionFixtureBuilder

  test "create and show expose supervision sessions through public ids only" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)

    post "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions",
      headers: app_api_headers(registration[:session_token]),
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    session_id = response_body.dig("conversation_supervision_session", "supervision_session_id")

    assert_equal "conversation_supervision_session_create", response_body.fetch("method_id")
    assert_equal fixture[:conversation].public_id, response_body.fetch("conversation_id")
    assert_equal session_id, response_body.dig("conversation_supervision_session", "supervision_session_id")
    assert_equal fixture[:conversation].public_id, response_body.dig("conversation_supervision_session", "target_conversation_id")
    assert_equal fixture[:user].public_id, response_body.dig("conversation_supervision_session", "initiator_id")
    assert_equal "open", response_body.dig("conversation_supervision_session", "lifecycle_state")
    assert_equal "summary_model", response_body.dig("conversation_supervision_session", "responder_strategy")
    assert_equal({
      "supervision_enabled" => true,
      "detailed_progress_enabled" => true,
      "side_chat_enabled" => true,
      "control_enabled" => false,
    }, response_body.dig("conversation_supervision_session", "capability_policy_snapshot"))
    refute_includes response.body, %("#{fixture[:conversation].id}")

    get "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session_id}",
      headers: app_api_headers(registration[:session_token])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_supervision_session_show", response_body.fetch("method_id")
    assert_equal session_id, response_body.dig("conversation_supervision_session", "supervision_session_id")
    assert_equal fixture[:conversation].public_id, response_body.dig("conversation_supervision_session", "target_conversation_id")
  end

  test "rejects unsupported responder strategies" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)

    post "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions",
      params: {
        responder_strategy: "agent_contract",
      },
      headers: app_api_headers(registration[:session_token]),
      as: :json

    assert_response :unprocessable_entity
    assert_includes response.body, "unsupported supervision responder strategy"
  end

  test "rejects raw bigint identifiers for create and show" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)

    post "/app_api/conversations/#{fixture[:conversation].id}/supervision_sessions",
      headers: app_api_headers(registration[:session_token]),
      as: :json

    assert_response :not_found

    get "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.id}",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found
  end

  test "returns gone for closed supervision sessions and not found when the target conversation is missing" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)
    session.update!(lifecycle_state: "closed")

    get "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.public_id}",
      headers: app_api_headers(registration[:session_token])

    assert_response :gone

    ActiveRecord::Base.connection_pool.with_connection do |connection|
      connection.disable_referential_integrity do
        Conversation.unscoped.where(id: fixture[:conversation].id).delete_all
      end
    end

    get "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.public_id}",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found
  end

  test "close transitions the session to closed using public ids only" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)

    post "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.public_id}/close",
      headers: app_api_headers(registration[:session_token]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_supervision_session_close", response_body.fetch("method_id")
    assert_equal session.public_id, response_body.dig("conversation_supervision_session", "supervision_session_id")
    assert_equal "closed", response_body.dig("conversation_supervision_session", "lifecycle_state")
    assert response_body.dig("conversation_supervision_session", "closed_at").present?
    assert_equal "closed", session.reload.lifecycle_state
    assert session.closed_at.present?

    post "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.id}/close",
      headers: app_api_headers(registration[:session_token]),
      as: :json

    assert_response :not_found
  end

  test "returns not found when the conversation becomes inaccessible after an agent visibility change" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)
    replacement_owner = create_user!(
      installation: fixture[:installation],
      identity: create_identity!,
      display_name: "Replacement Owner"
    )

    fixture[:agent].update!(
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: replacement_owner
    )

    post "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions",
      headers: app_api_headers(registration[:session_token]),
      as: :json

    assert_response :not_found

    get "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.public_id}",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found

    post "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.public_id}/close",
      headers: app_api_headers(registration[:session_token]),
      as: :json

    assert_response :not_found
  end

  test "returns not found when a session is requested through the wrong conversation scope" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)
    other_conversation = create_conversation_record!(
      workspace: fixture[:workspace],
      agent_definition_version: fixture[:agent_definition_version],
      execution_runtime: fixture[:execution_runtime]
    )

    get "/app_api/conversations/#{other_conversation.public_id}/supervision_sessions/#{session.public_id}",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found

    post "/app_api/conversations/#{other_conversation.public_id}/supervision_sessions/#{session.public_id}/close",
      headers: app_api_headers(registration[:session_token]),
      as: :json

    assert_response :not_found
  end

  test "shows a supervision session within six SQL queries" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)

    assert_sql_query_count_at_most(6) do
      get "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions/#{session.public_id}",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success
  end
end
