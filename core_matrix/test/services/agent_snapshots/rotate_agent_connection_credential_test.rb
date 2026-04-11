require "test_helper"

module AgentSnapshots
end

class AgentSnapshots::RotateAgentConnectionCredentialTest < ActiveSupport::TestCase
  test "issues a fresh connection credential and invalidates the previous secret atomically" do
    registration = register_agent_runtime!
    previous_credential = registration[:agent_connection_credential]

    result = AgentSnapshots::RotateAgentConnectionCredential.call(
      agent_snapshot: registration[:agent_snapshot],
      actor: registration[:actor]
    )

    assert result.agent_connection_credential.present?
    refute_equal previous_credential, result.agent_connection_credential
    assert registration[:agent_snapshot].reload.matches_agent_connection_credential?(result.agent_connection_credential)
    refute registration[:agent_snapshot].matches_agent_connection_credential?(previous_credential)
    assert_nil AgentSnapshot.find_by_agent_connection_credential(previous_credential)

    audit_log = AuditLog.find_by!(action: "agent_snapshot.agent_connection_credential_rotated")
    assert_equal registration[:agent_connection], audit_log.subject
    assert_equal registration[:actor], audit_log.actor
  end
end
