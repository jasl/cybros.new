require "test_helper"

class AppApiSessionsTest < ActionDispatch::IntegrationTest
  test "login issues a session token for a valid identity" do
    installation = create_installation!(name: "Primary Installation")
    identity = create_identity!(email: "admin@example.com", password: "Password123!")
    user = create_user!(installation: installation, identity: identity, role: "admin", display_name: "Primary Admin")

    assert_difference("Session.count", +1) do
      post "/app_api/session",
        params: {
          email: "admin@example.com",
          password: "Password123!",
        },
        as: :json
    end

    assert_response :created

    response_body = response.parsed_body
    assert_equal "session_create", response_body.fetch("method_id")
    assert_equal user.public_id, response_body.dig("user", "user_id")
    assert_equal installation.name, response_body.dig("installation", "name")
    assert response_body.fetch("session_token").present?
    refute_includes response.body, %("#{user.id}")
    refute_includes response.body, %("#{installation.id}")
  end

  test "login rejects invalid credentials" do
    create_identity!(email: "admin@example.com", password: "Password123!")

    post "/app_api/session",
      params: {
        email: "admin@example.com",
        password: "wrong-password",
      },
      as: :json

    assert_response :unauthorized
    assert_equal "invalid email or password", response.parsed_body.fetch("error")
  end

  test "whoami returns the current authenticated session summary" do
    installation = create_installation!(name: "Primary Installation")
    user = create_user!(installation: installation, role: "admin", display_name: "Primary Admin")
    session = create_session!(user: user)

    get "/app_api/session", headers: app_api_headers(session.plaintext_token)

    assert_response :success

    response_body = response.parsed_body
    assert_equal "session_show", response_body.fetch("method_id")
    assert_equal session.public_id, response_body.dig("session", "session_id")
    assert_equal user.public_id, response_body.dig("user", "user_id")
    assert_equal installation.name, response_body.dig("installation", "name")
    assert_nil response_body["session_token"]
  end

  test "logout revokes the current session" do
    session = create_session!(user: create_user!(role: "admin"))

    delete "/app_api/session", headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal "session_destroy", response.parsed_body.fetch("method_id")
    assert_predicate session.reload, :revoked?
  end
end
