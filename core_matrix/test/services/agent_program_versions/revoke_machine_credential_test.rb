require "test_helper"

module AgentProgramVersions
end

class AgentProgramVersions::RevokeMachineCredentialTest < ActiveSupport::TestCase
  test "makes the current machine credential unusable before any later re-registration" do
    registration = register_agent_runtime!
    current_credential = registration[:machine_credential]

    AgentProgramVersions::RevokeMachineCredential.call(
      deployment: registration[:deployment],
      actor: registration[:actor]
    )

    deployment = registration[:deployment].reload
    assert deployment.offline?
    assert_equal "machine_credential_revoked", deployment.unavailability_reason
    refute deployment.matches_machine_credential?(current_credential)
    assert_nil AgentProgramVersion.find_by_machine_credential(current_credential)

    audit_log = AuditLog.find_by!(action: "agent_program_version.machine_credential_revoked")
    assert_equal registration[:agent_session], audit_log.subject
    assert_equal registration[:actor], audit_log.actor
  end
end
