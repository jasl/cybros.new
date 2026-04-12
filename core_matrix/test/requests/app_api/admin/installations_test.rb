require "test_helper"

class AppApiAdminInstallationsTest < ActionDispatch::IntegrationTest
  test "shows the installation overview for an admin" do
    installation = create_installation!(name: "Core Matrix")
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)
    create_agent!(installation: installation, display_name: "Alpha Agent")
    create_execution_runtime!(installation: installation, display_name: "Desk Runtime")
    OnboardingSessions::Issue.call(
      installation: installation,
      target_kind: "execution_runtime",
      issued_by: admin,
      expires_at: 2.hours.from_now
    )

    get "/app_api/admin/installation", headers: app_api_headers(session.plaintext_token)

    assert_response :success

    response_body = response.parsed_body
    assert_equal "admin_installation_show", response_body.fetch("method_id")
    assert_equal "Core Matrix", response_body.dig("installation", "name")
    assert_equal "bootstrapped", response_body.dig("installation", "bootstrap_state")
    assert_equal 1, response_body.dig("installation", "agents_count")
    assert_equal 1, response_body.dig("installation", "execution_runtimes_count")
    assert_equal 1, response_body.dig("installation", "onboarding_sessions_count")
    refute_includes response.body, %("#{installation.id}")
  end

  test "rejects a non-admin installation overview request" do
    installation = create_installation!
    member = create_user!(installation: installation, role: "member")
    session = create_session!(user: member)

    get "/app_api/admin/installation", headers: app_api_headers(session.plaintext_token)

    assert_response :forbidden
    assert_equal "admin access is required", response.parsed_body.fetch("error")
  end
end
