require "test_helper"

class AppApiAuthenticationTest < ActionDispatch::IntegrationTest
  include ConversationSupervisionFixtureBuilder

  test "rejects agent connection credentials for app api requests" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    assert_nil Session.find_by_plaintext_token(registration[:agent_connection_credential])

    get "/app_api/conversations/#{context[:conversation].public_id}/transcript",
      headers: agent_api_headers(registration[:agent_connection_credential])

    assert_response :unauthorized
    assert_equal "session is required", response.parsed_body.fetch("error")
  end

  test "accepts a valid human session for app api requests" do
    context = build_canonical_variable_context!
    session = Session.issue_for!(
      identity: context[:user].identity,
      user: context[:user],
      expires_at: 30.days.from_now,
      metadata: {}
    )

    get "/app_api/conversations/#{context[:conversation].public_id}/transcript",
      headers: connection_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal "conversation_transcript_list", response.parsed_body.fetch("method_id")
  end

  test "cookie-backed app api writes require a csrf token" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    fixture = prepare_conversation_supervision_context!
    session = create_session!(user: fixture[:user])

    post "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions",
      headers: {
        "Cookie" => "#{SessionAuthentication::SESSION_COOKIE_KEY}=#{session.plaintext_token}",
        "Accept" => "application/json",
      },
      as: :json

    assert_response :unprocessable_entity
    assert_equal "csrf token is invalid", response.parsed_body.fetch("error")
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  test "authorization-header app api writes do not require a csrf token" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    fixture = prepare_conversation_supervision_context!
    session = create_session!(user: fixture[:user])

    post "/app_api/conversations/#{fixture[:conversation].public_id}/supervision_sessions",
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :created
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
