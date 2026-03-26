require "test_helper"

class ExternalFenixPairingFlowTest < ActionDispatch::IntegrationTest
  test "same installation registration supports upgrade and downgrade rotation" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_installation = create_agent_installation!(installation: installation)

    first = register_runtime!(
      installation: installation,
      actor: actor,
      agent_installation: agent_installation,
      sdk_version: "fenix-0.1.0",
      base_url: "https://fenix-v1.example.test"
    )
    AgentDeployments::RecordHeartbeat.call(
      deployment: first[:deployment],
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.1.0" },
      auto_resume_eligible: true
    )

    upgrade = register_runtime!(
      installation: installation,
      actor: actor,
      agent_installation: agent_installation,
      sdk_version: "fenix-0.2.0",
      base_url: "https://fenix-v2.example.test"
    )
    AgentDeployments::RecordHeartbeat.call(
      deployment: upgrade[:deployment],
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.2.0" },
      auto_resume_eligible: true
    )

    assert_equal "superseded", first[:deployment].reload.bootstrap_state
    assert_equal "active", upgrade[:deployment].reload.bootstrap_state
    assert_equal first[:execution_environment].public_id, upgrade[:execution_environment].public_id

    downgrade = register_runtime!(
      installation: installation,
      actor: actor,
      agent_installation: agent_installation,
      sdk_version: "fenix-0.0.9",
      base_url: "https://fenix-v0.example.test"
    )
    AgentDeployments::RecordHeartbeat.call(
      deployment: downgrade[:deployment],
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.0.9" },
      auto_resume_eligible: true
    )

    assert_equal "superseded", upgrade[:deployment].reload.bootstrap_state
    assert_equal "active", downgrade[:deployment].reload.bootstrap_state
    assert_equal first[:execution_environment].public_id, downgrade[:execution_environment].public_id
  end

  test "manual retry can move paused work onto a rotated external fenix deployment" do
    context = prepare_workflow_execution_context!(create_workspace_context!)
    actor = create_user!(installation: context[:installation], role: "admin")
    rotated = register_runtime!(
      installation: context[:installation],
      actor: actor,
      agent_installation: context[:agent_installation],
      sdk_version: "fenix-0.2.0",
      base_url: "https://fenix-v2.example.test"
    )
    AgentDeployments::RecordHeartbeat.call(
      deployment: rotated[:deployment],
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.2.0" },
      auto_resume_eligible: true
    )

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Retry after rotation",
      agent_deployment: context[:agent_deployment],
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
    AgentDeployments::MarkUnavailable.call(
      deployment: context[:agent_deployment],
      severity: "prolonged",
      reason: "runtime_offline",
      occurred_at: Time.current
    )

    retried = Workflows::ManualRetry.call(
      workflow_run: workflow_run.reload,
      deployment: rotated[:deployment],
      actor: actor,
      selector: "role:main"
    )

    assert retried.active?
    assert_equal rotated[:deployment], retried.turn.agent_deployment
    assert_equal "fenix-0.2.0", rotated[:deployment].sdk_version
  end

  private

  def register_runtime!(installation:, actor:, agent_installation:, sdk_version:, base_url:)
    register_agent_runtime!(
      installation: installation,
      actor: actor,
      agent_installation: agent_installation,
      environment_fingerprint: "fenix-host-a",
      sdk_version: sdk_version,
      fingerprint: "fenix-release-#{sdk_version}",
      endpoint_metadata: {
        "transport" => "http",
        "base_url" => base_url,
      }
    )
  end
end
