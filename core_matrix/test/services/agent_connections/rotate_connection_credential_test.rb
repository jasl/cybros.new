require "test_helper"

module AgentConnections
end

class AgentConnections::RotateConnectionCredentialTest < ActiveSupport::TestCase
  test "issues a fresh connection credential and invalidates the previous secret atomically" do
    registration = register_agent_runtime!
    previous_credential = registration[:agent_connection_credential]

    result = AgentConnections::RotateConnectionCredential.call(
      agent_definition_version: registration[:agent_definition_version],
      actor: registration[:actor]
    )

    assert result.agent_connection_credential.present?
    refute_equal previous_credential, result.agent_connection_credential
    assert registration[:agent_definition_version].reload.matches_agent_connection_credential?(result.agent_connection_credential)
    refute registration[:agent_definition_version].matches_agent_connection_credential?(previous_credential)
    assert_nil AgentDefinitionVersion.find_by_agent_connection_credential(previous_credential)

    audit_log = AuditLog.find_by!(action: "agent_connection.credential_rotated")
    assert_equal registration[:agent_connection], audit_log.subject
    assert_equal registration[:actor], audit_log.actor
  end
end
