require "test_helper"

module OnboardingSessions
end

class OnboardingSessions::IssueTest < ActiveSupport::TestCase
  test "issues an agent onboarding session token and writes an audit row" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)

    onboarding_session = OnboardingSessions::Issue.call(
      installation: installation,
      target_kind: "agent",
      target: agent,
      issued_by: actor,
      expires_at: 2.hours.from_now
    )

    assert onboarding_session.matches_token?(onboarding_session.plaintext_token)
    assert_equal "agent", onboarding_session.target_kind
    assert_equal agent, onboarding_session.target_agent

    audit_log = AuditLog.find_by!(action: "onboarding_session.issued")
    assert_equal actor, audit_log.actor
    assert_equal onboarding_session, audit_log.subject
  end

  test "issues a runtime onboarding session without requiring an agent target" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")

    onboarding_session = OnboardingSessions::Issue.call(
      installation: installation,
      target_kind: "execution_runtime",
      target: nil,
      issued_by: actor,
      expires_at: 2.hours.from_now
    )

    assert_equal "execution_runtime", onboarding_session.target_kind
    assert_nil onboarding_session.target_agent
    assert_nil onboarding_session.target_execution_runtime
  end
end
