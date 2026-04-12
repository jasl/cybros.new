require "test_helper"

module AgentConnections
end

class AgentConnections::RevokeConnectionCredentialTest < ActiveSupport::TestCase
  test "makes the current connection credential unusable before any later re-registration" do
    registration = register_agent_runtime!
    current_credential = registration[:agent_connection_credential]

    AgentConnections::RevokeConnectionCredential.call(
      agent_definition_version: registration[:agent_definition_version],
      actor: registration[:actor]
    )

    agent_definition_version = registration[:agent_definition_version].reload
    assert agent_definition_version.offline?
    assert_equal "agent_connection_credential_revoked", agent_definition_version.unavailability_reason
    refute agent_definition_version.matches_agent_connection_credential?(current_credential)
    assert_nil AgentDefinitionVersion.find_by_agent_connection_credential(current_credential)

    audit_log = AuditLog.find_by!(action: "agent_connection.credential_revoked")
    assert_equal registration[:agent_connection], audit_log.subject
    assert_equal registration[:actor], audit_log.actor
  end
end
