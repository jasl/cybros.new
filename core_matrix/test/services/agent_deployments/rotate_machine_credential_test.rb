require "test_helper"

module AgentDeployments
end

class AgentDeployments::RotateMachineCredentialTest < ActiveSupport::TestCase
  test "issues a fresh machine credential and invalidates the previous secret atomically" do
    registration = register_agent_runtime!
    previous_credential = registration[:machine_credential]

    result = AgentDeployments::RotateMachineCredential.call(
      deployment: registration[:deployment],
      actor: registration[:actor]
    )

    assert result.machine_credential.present?
    refute_equal previous_credential, result.machine_credential
    assert registration[:deployment].reload.matches_machine_credential?(result.machine_credential)
    refute registration[:deployment].matches_machine_credential?(previous_credential)
    assert_nil AgentDeployment.find_by_machine_credential(previous_credential)

    audit_log = AuditLog.find_by!(action: "agent_deployment.machine_credential_rotated")
    assert_equal registration[:deployment], audit_log.subject
    assert_equal registration[:actor], audit_log.actor
  end
end
