require "test_helper"

class AppApiAdminOnboardingSessionsTest < ActionDispatch::IntegrationTest
  test "lists both agent and execution runtime onboarding sessions through one resource family" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)
    runtime = create_execution_runtime!(installation: installation, display_name: "Desk Runtime")
    agent = create_agent!(installation: installation, display_name: "Alpha Agent")
    agent_session = OnboardingSessions::Issue.call(
      installation: installation,
      target_kind: "agent",
      target: agent,
      issued_by: admin,
      expires_at: 2.hours.from_now
    )
    runtime_session = OnboardingSessions::Issue.call(
      installation: installation,
      target_kind: "execution_runtime",
      target: runtime,
      issued_by: admin,
      expires_at: 2.hours.from_now
    )

    get "/app_api/admin/onboarding_sessions", headers: app_api_headers(session.plaintext_token)

    assert_response :success

    response_body = response.parsed_body
    assert_equal "admin_onboarding_session_index", response_body.fetch("method_id")
    assert_equal [agent_session.public_id, runtime_session.public_id], response_body.fetch("onboarding_sessions").map { |item| item.fetch("onboarding_session_id") }
    assert_equal %w[agent execution_runtime], response_body.fetch("onboarding_sessions").map { |item| item.fetch("target_kind") }
    refute_includes response.body, %("#{agent_session.id}")
    refute_includes response.body, %("#{runtime_session.id}")
  end

  test "rejects a non-admin onboarding session list request" do
    installation = create_installation!
    member = create_user!(installation: installation, role: "member")
    session = create_session!(user: member)

    get "/app_api/admin/onboarding_sessions", headers: app_api_headers(session.plaintext_token)

    assert_response :forbidden
    assert_equal "admin access is required", response.parsed_body.fetch("error")
  end
end
