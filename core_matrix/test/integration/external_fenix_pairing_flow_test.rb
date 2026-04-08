require "test_helper"

class ExternalFenixPairingFlowTest < ActionDispatch::IntegrationTest
  test "same installation registration supports upgrade and downgrade rotation" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_program = create_agent_program!(installation: installation)

    first = register_runtime!(
      installation: installation,
      actor: actor,
      agent_program: agent_program,
      sdk_version: "fenix-0.1.0",
      base_url: "https://fenix-v1.example.test"
    )
    AgentProgramVersions::RecordHeartbeat.call(
      deployment: first[:deployment],
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.1.0" },
      auto_resume_eligible: true
    )

    upgrade = register_runtime!(
      installation: installation,
      actor: actor,
      agent_program: agent_program,
      sdk_version: "fenix-0.2.0",
      base_url: "https://fenix-v2.example.test"
    )
    AgentProgramVersions::RecordHeartbeat.call(
      deployment: upgrade[:deployment],
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.2.0" },
      auto_resume_eligible: true
    )

    assert_equal "superseded", first[:deployment].reload.bootstrap_state
    assert_equal "active", upgrade[:deployment].reload.bootstrap_state
    assert_equal first[:executor_program].public_id, upgrade[:executor_program].public_id

    downgrade = register_runtime!(
      installation: installation,
      actor: actor,
      agent_program: agent_program,
      sdk_version: "fenix-0.0.9",
      base_url: "https://fenix-v0.example.test"
    )
    AgentProgramVersions::RecordHeartbeat.call(
      deployment: downgrade[:deployment],
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.0.9" },
      auto_resume_eligible: true
    )

    assert_equal "superseded", upgrade[:deployment].reload.bootstrap_state
    assert_equal "active", downgrade[:deployment].reload.bootstrap_state
    assert_equal first[:executor_program].public_id, downgrade[:executor_program].public_id
  end

  test "manual retry can move paused work onto a rotated external fenix deployment" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Retry after rotation",
      agent_program_version: context[:agent_program_version],
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
      agent_program: context[:agent_program],
      executor_program: context[:executor_program],
      sdk_version: "fenix-0.2.0",
      base_url: "https://fenix-v2.example.test"
    )
    AgentProgramVersions::RecordHeartbeat.call(
      deployment: rotated[:deployment],
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.2.0" },
      auto_resume_eligible: true
    )
    AgentProgramVersions::MarkUnavailable.call(
      deployment: context[:agent_program_version],
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
    assert_equal rotated[:deployment], retried.turn.agent_program_version
    assert_equal "fenix-0.2.0", rotated[:deployment].sdk_version
  end

  private

  def register_runtime!(installation:, actor:, agent_program:, sdk_version:, base_url:, executor_program: nil)
    register_agent_runtime!(
      installation: installation,
      actor: actor,
      agent_program: agent_program,
      executor_program: executor_program,
      executor_fingerprint: executor_program&.executor_fingerprint || "fenix-host-a",
      sdk_version: sdk_version,
      fingerprint: "fenix-release-#{sdk_version}",
      endpoint_metadata: {
        "transport" => "http",
        "base_url" => base_url,
      }
    )
  end
end
