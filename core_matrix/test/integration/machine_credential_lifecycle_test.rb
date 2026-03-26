require "test_helper"

class MachineCredentialLifecycleTest < ActionDispatch::IntegrationTest
  test "rotation revocation and retirement preserve auditability and block future scheduling" do
    context = prepare_workflow_execution_context!(create_workspace_context!)
    admin = create_user!(installation: context[:installation], role: "admin")
    registration = register_agent_runtime!(
      installation: context[:installation],
      actor: admin,
      agent_installation: context[:agent_installation],
      execution_environment: context[:execution_environment]
    )
    rotated = AgentDeployments::RotateMachineCredential.call(
      deployment: registration[:deployment],
      actor: registration[:actor]
    )

    refute registration[:deployment].reload.matches_machine_credential?(registration[:machine_credential])
    assert registration[:deployment].matches_machine_credential?(rotated.machine_credential)

    AgentDeployments::RevokeMachineCredential.call(
      deployment: registration[:deployment],
      actor: registration[:actor]
    )

    refute registration[:deployment].reload.matches_machine_credential?(rotated.machine_credential)
    assert_nil AgentDeployment.find_by_machine_credential(rotated.machine_credential)

    AgentDeployments::Retire.call(
      deployment: context[:agent_deployment],
      actor: context[:user]
    )

    future_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    future_turn = Turns::StartUserTurn.call(
      conversation: future_conversation,
      content: "Retry on retired deployment",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::CreateForTurn.call(
        turn: future_turn,
        root_node_key: "root",
        root_node_type: "turn_root",
        decision_source: "system",
        metadata: {}
      )
    end

    assert_includes error.record.errors[:resolved_model_selection_snapshot], "agent deployment is not eligible for future scheduling"
    assert_equal 1, AuditLog.where(action: "agent_deployment.machine_credential_rotated").count
    assert_equal 1, AuditLog.where(action: "agent_deployment.machine_credential_revoked").count
    assert_equal 1, AuditLog.where(action: "agent_deployment.retired").count
  end
end
