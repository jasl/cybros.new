require "test_helper"

class AgentConnectionCredentialLifecycleTest < ActionDispatch::IntegrationTest
  test "rotation revocation and retirement preserve auditability and block future scheduling" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    admin = create_user!(installation: context[:installation], role: "admin")
    registration = register_agent_runtime!(
      installation: context[:installation],
      actor: admin,
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    rotated = AgentSnapshots::RotateAgentConnectionCredential.call(
      agent_snapshot: registration[:agent_snapshot],
      actor: registration[:actor]
    )

    refute registration[:agent_snapshot].reload.matches_agent_connection_credential?(registration[:agent_connection_credential])
    assert registration[:agent_snapshot].matches_agent_connection_credential?(rotated.agent_connection_credential)

    AgentSnapshots::RevokeAgentConnectionCredential.call(
      agent_snapshot: registration[:agent_snapshot],
      actor: registration[:actor]
    )

    refute registration[:agent_snapshot].reload.matches_agent_connection_credential?(rotated.agent_connection_credential)
    assert_nil AgentSnapshot.find_by_agent_connection_credential(rotated.agent_connection_credential)

    AgentSnapshots::Retire.call(
      agent_snapshot: registration[:agent_snapshot],
      actor: context[:user]
    )

    future_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartUserTurn.call(
        conversation: future_conversation,
        content: "Retry on retired agent snapshot",
        execution_runtime: context[:execution_runtime],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:agent], "must have an active agent connection for turn entry"
    assert_equal 1, AuditLog.where(action: "agent_snapshot.agent_connection_credential_rotated").count
    assert_equal 1, AuditLog.where(action: "agent_snapshot.agent_connection_credential_revoked").count
    assert_equal 1, AuditLog.where(action: "agent_snapshot.retired").count
  end
end
