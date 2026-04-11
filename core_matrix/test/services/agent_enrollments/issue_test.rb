require "test_helper"

module AgentEnrollments
end

class AgentEnrollments::IssueTest < ActiveSupport::TestCase
  test "issues an enrollment token and writes an audit row" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)

    enrollment = AgentEnrollments::Issue.call(
      agent: agent,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    assert enrollment.matches_token?(enrollment.plaintext_token)

    audit_log = AuditLog.find_by!(action: "agent_enrollment.issued")
    assert_equal actor, audit_log.actor
    assert_equal enrollment, audit_log.subject
  end
end
