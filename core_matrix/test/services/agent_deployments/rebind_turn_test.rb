require "test_helper"

class AgentDeployments::RebindTurnTest < ActiveSupport::TestCase
  test "switches the conversation deployment and rebuilds the paused turn snapshot from one canonical mutation owner" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation],
      execution_environment: context[:execution_environment]
    )
    AgentDeployments::RecordHeartbeat.call(
      deployment: replacement,
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )
    recovery_target = AgentDeploymentRecoveryTarget.new(
      agent_deployment: replacement,
      resolved_model_selection_snapshot: resolved_snapshot_for(
        turn: context[:turn],
        agent_deployment: replacement,
        selector_source: "manual_recovery",
        selector: "role:planner"
      ),
      selector_source: "manual_recovery",
      rebind_turn: true
    )

    rebound_turn = AgentDeployments::RebindTurn.call(
      turn: context[:turn],
      recovery_target: recovery_target
    )

    assert_equal replacement, context[:conversation].reload.agent_deployment
    assert_equal replacement, rebound_turn.reload.agent_deployment
    assert_equal replacement.fingerprint, rebound_turn.pinned_deployment_fingerprint
    assert_equal "role:planner", rebound_turn.normalized_selector
    assert_equal replacement.public_id, rebound_turn.execution_snapshot.identity["agent_deployment_id"]
  end

  private

  def resolved_snapshot_for(turn:, agent_deployment:, selector_source:, selector:)
    probe_turn = turn.dup
    probe_turn.installation = turn.installation
    probe_turn.conversation = turn.conversation
    probe_turn.agent_deployment = agent_deployment
    probe_turn.pinned_deployment_fingerprint = agent_deployment.fingerprint
    probe_turn.resolved_config_snapshot = turn.resolved_config_snapshot.deep_dup
    probe_turn.resolved_model_selection_snapshot = turn.resolved_model_selection_snapshot.deep_dup

    Workflows::ResolveModelSelector.call(
      turn: probe_turn,
      selector_source: selector_source,
      selector: selector
    )
  end
end
