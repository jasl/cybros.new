require "test_helper"

module PairingSessions
end

class PairingSessions::IssueTest < ActiveSupport::TestCase
  test "issues a pairing session token and writes an audit row" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)

    pairing_session = PairingSessions::Issue.call(
      agent: agent,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    assert pairing_session.matches_token?(pairing_session.plaintext_token)

    audit_log = AuditLog.find_by!(action: "pairing_session.issued")
    assert_equal actor, audit_log.actor
    assert_equal pairing_session, audit_log.subject
  end
end
