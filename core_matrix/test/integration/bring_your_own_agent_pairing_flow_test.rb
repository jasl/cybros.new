require "test_helper"

class BringYourOwnAgentPairingFlowTest < ActionDispatch::IntegrationTest
  test "same installation registration supports upgrade and downgrade rotation" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)

    first = register_runtime!(
      installation: installation,
      actor: actor,
      agent: agent,
      sdk_version: "fenix-0.1.0",
      base_url: "https://fenix-v1.example.test"
    )
    first_agent_definition_version = first.fetch(:agent_definition_version)
    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: first_agent_definition_version,
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.1.0" },
      auto_resume_eligible: true
    )

    upgrade = register_runtime!(
      installation: installation,
      actor: actor,
      agent: agent,
      sdk_version: "fenix-0.2.0",
      base_url: "https://fenix-v2.example.test"
    )
    upgraded_agent_definition_version = upgrade.fetch(:agent_definition_version)
    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: upgraded_agent_definition_version,
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.2.0" },
      auto_resume_eligible: true
    )

    assert_equal "superseded", first_agent_definition_version.reload.bootstrap_state
    assert_equal "active", upgraded_agent_definition_version.reload.bootstrap_state
    assert_equal first[:execution_runtime].public_id, upgrade[:execution_runtime].public_id

    downgrade = register_runtime!(
      installation: installation,
      actor: actor,
      agent: agent,
      sdk_version: "fenix-0.0.9",
      base_url: "https://fenix-v0.example.test"
    )
    downgraded_agent_definition_version = downgrade.fetch(:agent_definition_version)
    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: downgraded_agent_definition_version,
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.0.9" },
      auto_resume_eligible: true
    )

    assert_equal "superseded", upgraded_agent_definition_version.reload.bootstrap_state
    assert_equal "active", downgraded_agent_definition_version.reload.bootstrap_state
    assert_equal first[:execution_runtime].public_id, downgrade[:execution_runtime].public_id
  end

  test "manual retry can move paused work onto a rotated bring-your-own agent definition version" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    initial_agent_definition_version = context.fetch(:agent_definition_version)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Retry after rotation",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {}
    )
    actor = create_user!(installation: context[:installation], role: "admin")
    rotated = register_runtime!(
      installation: context[:installation],
      actor: actor,
      agent: context[:agent],
      execution_runtime: context[:execution_runtime],
      sdk_version: "fenix-0.2.0",
      base_url: "https://fenix-v2.example.test"
    )
    rotated_agent_definition_version = rotated.fetch(:agent_definition_version)
    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: rotated_agent_definition_version,
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.2.0" },
      auto_resume_eligible: true
    )
    AgentDefinitionVersions::MarkUnavailable.call(
      agent_definition_version: initial_agent_definition_version,
      severity: "prolonged",
      reason: "runtime_offline",
      occurred_at: Time.current
    )

    retried = Workflows::ManualRetry.call(
      workflow_run: workflow_run.reload,
      agent_definition_version: rotated_agent_definition_version,
      actor: actor,
      selector: "role:main"
    )

    assert retried.active?
    assert_equal rotated_agent_definition_version, retried.turn.agent_definition_version
    assert_equal "fenix-0.2.0", rotated_agent_definition_version.sdk_version
  end

  private

  def register_runtime!(installation:, actor:, agent:, sdk_version:, base_url:, execution_runtime: nil)
    register_agent_runtime!(
      installation: installation,
      actor: actor,
      agent: agent,
      execution_runtime: execution_runtime,
      execution_runtime_fingerprint: execution_runtime&.execution_runtime_fingerprint || "fenix-host-a",
      sdk_version: sdk_version,
      fingerprint: "fenix-release-#{sdk_version}",
      endpoint_metadata: {
        "transport" => "http",
        "base_url" => base_url,
      }
    )
  end
end
