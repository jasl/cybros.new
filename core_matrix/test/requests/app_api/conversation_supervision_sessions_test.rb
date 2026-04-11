require "test_helper"

class AppApiConversationSupervisionSessionsTest < ActionDispatch::IntegrationTest
  include ConversationSupervisionFixtureBuilder

  test "create and show expose supervision sessions through public ids only" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)

    post "/app_api/conversation_supervision_sessions",
      params: {
        conversation_id: fixture[:conversation].public_id,
      },
      headers: app_api_headers(registration[:agent_connection_credential]),
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

    get "/app_api/conversation_supervision_sessions/#{session_id}",
      headers: app_api_headers(registration[:agent_connection_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_supervision_session_show", response_body.fetch("method_id")
    assert_equal session_id, response_body.dig("conversation_supervision_session", "supervision_session_id")
    assert_equal fixture[:conversation].public_id, response_body.dig("conversation_supervision_session", "target_conversation_id")
  end

  test "rejects unsupported responder strategies" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)

    post "/app_api/conversation_supervision_sessions",
      params: {
        conversation_id: fixture[:conversation].public_id,
        responder_strategy: "program_contract",
      },
      headers: app_api_headers(registration[:agent_connection_credential]),
      as: :json

    assert_response :unprocessable_entity
    assert_includes response.body, "unsupported supervision responder strategy"
  end

  test "rejects raw bigint identifiers for create and show" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)

    post "/app_api/conversation_supervision_sessions",
      params: {
        conversation_id: fixture[:conversation].id,
      },
      headers: app_api_headers(registration[:agent_connection_credential]),
      as: :json

    assert_response :not_found

    get "/app_api/conversation_supervision_sessions/#{session.id}",
      headers: app_api_headers(registration[:agent_connection_credential])

    assert_response :not_found
  end

  test "returns gone for closed supervision sessions and not found when the target conversation is missing" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)
    session.update!(lifecycle_state: "closed")

    get "/app_api/conversation_supervision_sessions/#{session.public_id}",
      headers: app_api_headers(registration[:agent_connection_credential])

    assert_response :gone

    ActiveRecord::Base.connection_pool.with_connection do |connection|
      connection.disable_referential_integrity do
        Conversation.unscoped.where(id: fixture[:conversation].id).delete_all
      end
    end

    get "/app_api/conversation_supervision_sessions/#{session.public_id}",
      headers: app_api_headers(registration[:agent_connection_credential])

    assert_response :not_found
  end

  test "close transitions the session to closed using public ids only" do
    fixture = prepare_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    session = create_conversation_supervision_session!(fixture)

    post "/app_api/conversation_supervision_sessions/#{session.public_id}/close",
      headers: app_api_headers(registration[:agent_connection_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_supervision_session_close", response_body.fetch("method_id")
    assert_equal session.public_id, response_body.dig("conversation_supervision_session", "supervision_session_id")
    assert_equal "closed", response_body.dig("conversation_supervision_session", "lifecycle_state")
    assert response_body.dig("conversation_supervision_session", "closed_at").present?
    assert_equal "closed", session.reload.lifecycle_state
    assert session.closed_at.present?

    post "/app_api/conversation_supervision_sessions/#{session.id}/close",
      headers: app_api_headers(registration[:agent_connection_credential]),
      as: :json

    assert_response :not_found
  end
end
