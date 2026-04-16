require "test_helper"

class AppApiBootstrapTest < ActionDispatch::IntegrationTest
  test "bootstrap status reports unbootstrapped before any installation exists" do
    get "/app_api/bootstrap/status"

    assert_response :success
    assert_equal "bootstrap_status", response.parsed_body.fetch("method_id")
    assert_equal "unbootstrapped", response.parsed_body.fetch("bootstrap_state")
    assert_nil response.parsed_body["installation"]
  end

  test "bootstrap status reports bootstrapped when an installation exists" do
    installation = create_installation!(name: "Primary Installation")

    get "/app_api/bootstrap/status"

    assert_response :success
    assert_equal "bootstrap_status", response.parsed_body.fetch("method_id")
    assert_equal "bootstrapped", response.parsed_body.fetch("bootstrap_state")
    assert_equal "Primary Installation", response.parsed_body.dig("installation", "name")
    refute_includes response.body, %("#{installation.id}")
  end

  test "bootstrap creates first admin and returns a session token" do
    assert_difference(["Installation.count", "Identity.count", "User.count", "Session.count"], +1) do
      post "/app_api/bootstrap",
        params: {
          name: "Primary Installation",
          email: "admin@example.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          display_name: "Primary Admin",
        },
        as: :json
    end

    assert_response :created

    response_body = response.parsed_body
    assert_equal "bootstrap_create", response_body.fetch("method_id")
    assert_equal "bootstrapped", response_body.dig("installation", "bootstrap_state")
    assert_equal "admin@example.com", response_body.dig("user", "email")
    assert_equal "admin", response_body.dig("user", "role")
    assert response_body.fetch("session_token").present?

    session = Session.find_by_plaintext_token(response_body.fetch("session_token"))
    assert session.present?
    assert_equal "Primary Admin", session.user.display_name
    assert_equal "Primary Installation", session.user.installation.name

    refute_includes response.body, %("#{session.user.id}")
    refute_includes response.body, %("#{session.user.installation.id}")
  end

  test "bootstrap returns unprocessable entity after the installation already exists" do
    create_installation!

    post "/app_api/bootstrap",
      params: {
        name: "Another Installation",
        email: "admin@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        display_name: "Another Admin",
      },
      as: :json

    assert_response :unprocessable_entity
    assert_equal "installation already exists", response.parsed_body.fetch("error")
  end
end
