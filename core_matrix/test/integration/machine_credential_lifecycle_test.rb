require "test_helper"

class MachineCredentialLifecycleTest < ActionDispatch::IntegrationTest
  test "rotation revocation and retirement preserve auditability and block future scheduling" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    admin = create_user!(installation: context[:installation], role: "admin")
    registration = register_agent_runtime!(
      installation: context[:installation],
      actor: admin,
      agent_program: context[:agent_program],
      execution_runtime: context[:execution_runtime]
    )
    rotated = AgentProgramVersions::RotateMachineCredential.call(
      deployment: registration[:deployment],
      actor: registration[:actor]
    )

    refute registration[:deployment].reload.matches_machine_credential?(registration[:machine_credential])
    assert registration[:deployment].matches_machine_credential?(rotated.machine_credential)

    AgentProgramVersions::RevokeMachineCredential.call(
      deployment: registration[:deployment],
      actor: registration[:actor]
    )

    refute registration[:deployment].reload.matches_machine_credential?(rotated.machine_credential)
    assert_nil AgentProgramVersion.find_by_machine_credential(rotated.machine_credential)

    AgentProgramVersions::Retire.call(
      deployment: registration[:deployment],
      actor: context[:user]
    )

    future_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent_program: context[:agent_program]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartUserTurn.call(
        conversation: future_conversation,
        content: "Retry on retired deployment",
        execution_runtime: context[:execution_runtime],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:agent_program], "must have an active agent session for turn entry"
    assert_equal 1, AuditLog.where(action: "agent_program_version.machine_credential_rotated").count
    assert_equal 1, AuditLog.where(action: "agent_program_version.machine_credential_revoked").count
    assert_equal 1, AuditLog.where(action: "agent_program_version.retired").count
  end
end
