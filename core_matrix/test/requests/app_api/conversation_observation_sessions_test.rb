require "test_helper"

class AppApiConversationObservationSessionsTest < ActionDispatch::IntegrationTest
  test "create and show expose observation sessions through public ids only" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    post "/app_api/conversation_observation_sessions",
      params: {
        conversation_id: context[:conversation].public_id,
        responder_strategy: "builtin",
      },
      headers: app_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    session_id = response_body.dig("conversation_observation_session", "observation_session_id")

    assert_equal "conversation_observation_session_create", response_body.fetch("method_id")
    assert_equal context[:conversation].public_id, response_body.fetch("conversation_id")
    assert_equal session_id, response_body.dig("conversation_observation_session", "observation_session_id")
    assert_equal context[:conversation].public_id, response_body.dig("conversation_observation_session", "target_conversation_id")
    assert_equal context[:user].public_id, response_body.dig("conversation_observation_session", "initiator_id")
    assert_equal "open", response_body.dig("conversation_observation_session", "lifecycle_state")
    assert_equal "builtin", response_body.dig("conversation_observation_session", "responder_strategy")
    assert_equal({ "observe" => true, "control_enabled" => false }, response_body.dig("conversation_observation_session", "capability_policy_snapshot"))
    refute_includes response.body, %("#{context[:conversation].id}")

    get "/app_api/conversation_observation_sessions/#{session_id}",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_observation_session_show", response_body.fetch("method_id")
    assert_equal session_id, response_body.dig("conversation_observation_session", "observation_session_id")
    assert_equal context[:conversation].public_id, response_body.dig("conversation_observation_session", "target_conversation_id")
  end

  test "rejects unsupported responder strategies" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    post "/app_api/conversation_observation_sessions",
      params: {
        conversation_id: context[:conversation].public_id,
        responder_strategy: "program_contract",
      },
      headers: app_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :unprocessable_entity
    assert_includes response.body, "unsupported observation responder strategy"
  end

  test "rejects raw bigint identifiers for create and show" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    session = ConversationObservationSession.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {}
    )

    post "/app_api/conversation_observation_sessions",
      params: {
        conversation_id: context[:conversation].id,
      },
      headers: app_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :not_found

    get "/app_api/conversation_observation_sessions/#{session.id}",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :not_found
  end

  test "returns not found for missing observation conversations and sessions" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    post "/app_api/conversation_observation_sessions",
      params: {
        conversation_id: "missing-conversation",
        responder_strategy: "builtin",
      },
      headers: app_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :not_found

    get "/app_api/conversation_observation_sessions/missing-session",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :not_found
  end
end
