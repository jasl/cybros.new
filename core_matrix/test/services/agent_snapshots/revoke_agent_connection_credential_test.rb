require "test_helper"

module AgentSnapshots
end

class AgentSnapshots::RevokeAgentConnectionCredentialTest < ActiveSupport::TestCase
  test "makes the current connection credential unusable before any later re-registration" do
    registration = register_agent_runtime!
    current_credential = registration[:agent_connection_credential]

    AgentSnapshots::RevokeAgentConnectionCredential.call(
      agent_snapshot: registration[:agent_snapshot],
      actor: registration[:actor]
    )

    agent_snapshot = registration[:agent_snapshot].reload
    assert agent_snapshot.offline?
    assert_equal "agent_connection_credential_revoked", agent_snapshot.unavailability_reason
    refute agent_snapshot.matches_agent_connection_credential?(current_credential)
    assert_nil AgentSnapshot.find_by_agent_connection_credential(current_credential)

    audit_log = AuditLog.find_by!(action: "agent_snapshot.agent_connection_credential_revoked")
    assert_equal registration[:agent_connection], audit_log.subject
    assert_equal registration[:actor], audit_log.actor
  end
end
