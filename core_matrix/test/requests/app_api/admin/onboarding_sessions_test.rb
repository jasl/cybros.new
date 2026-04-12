require "test_helper"

class AppApiAdminOnboardingSessionsTest < ActionDispatch::IntegrationTest
  test "creates an execution runtime onboarding session and returns the plaintext token once" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)

    assert_difference("OnboardingSession.count", +1) do
      post "/app_api/admin/onboarding_sessions",
        params: {
          target_kind: "execution_runtime",
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json
    end

    assert_response :created

    response_body = response.parsed_body
    assert_equal "admin_onboarding_session_create", response_body.fetch("method_id")
    assert response_body.fetch("onboarding_token").present?
    onboarding_session = OnboardingSession.find_by_public_id!(
      response_body.dig("onboarding_session", "onboarding_session_id")
    )
    assert_equal "execution_runtime", onboarding_session.target_kind
    assert_nil onboarding_session.target_execution_runtime
    assert_equal admin, onboarding_session.issued_by_user
    assert_equal onboarding_session, OnboardingSession.find_by_plaintext_token(response_body.fetch("onboarding_token"))
  end

  test "creates an agent and issues an onboarding session for it" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)

    assert_difference(["Agent.count", "OnboardingSession.count"], +1) do
      post "/app_api/admin/onboarding_sessions",
        params: {
          target_kind: "agent",
          agent_key: "bring-your-own-agent",
          display_name: "Bring Your Own Agent",
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json
    end

    assert_response :created

    response_body = response.parsed_body
    assert_equal "admin_onboarding_session_create", response_body.fetch("method_id")
    assert response_body.fetch("onboarding_token").present?
    onboarding_session = OnboardingSession.find_by_public_id!(
      response_body.dig("onboarding_session", "onboarding_session_id")
    )
    agent = onboarding_session.target_agent
    assert_equal "agent", onboarding_session.target_kind
    assert_equal "bring-your-own-agent", agent.key
    assert_equal "Bring Your Own Agent", agent.display_name
    assert_equal "public", agent.visibility
    assert_equal "system", agent.provisioning_origin
    assert_equal "active", agent.lifecycle_state
  end

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
