require "test_helper"

class ExecutionIdentityRecovery::RebindTurnTest < ActiveSupport::TestCase
  test "switches the conversation agent definition version and rebuilds the paused turn snapshot from one canonical mutation owner" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: replacement,
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )
    recovery_target = ExecutionIdentityRecoveryTarget.new(
      agent_definition_version: replacement,
      resolved_model_selection_snapshot: resolved_snapshot_for(
        turn: context[:turn],
        agent_definition_version: replacement,
        selector_source: "manual_recovery",
        selector: "role:planner"
      ),
      selector_source: "manual_recovery",
      rebind_turn: true
    )

    rebound_turn = ExecutionIdentityRecovery::RebindTurn.call(
      turn: context[:turn],
      recovery_target: recovery_target
    )

    assert_equal replacement, rebound_turn.reload.agent_definition_version
    assert_equal replacement.fingerprint, rebound_turn.pinned_agent_definition_fingerprint
    assert_equal "role:planner", rebound_turn.normalized_selector
    assert_equal replacement.public_id, rebound_turn.execution_snapshot.identity["agent_definition_version_id"]
  end

  private

  def resolved_snapshot_for(turn:, agent_definition_version:, selector_source:, selector:)
    probe_turn = turn.dup
    probe_turn.installation = turn.installation
    probe_turn.conversation = turn.conversation
    probe_turn.agent_definition_version = agent_definition_version
    probe_turn.execution_runtime = turn.execution_runtime
    probe_turn.pinned_agent_definition_fingerprint = agent_definition_version.fingerprint
    probe_turn.resolved_config_snapshot = turn.resolved_config_snapshot.deep_dup
    probe_turn.resolved_model_selection_snapshot = turn.resolved_model_selection_snapshot.deep_dup

    Workflows::ResolveModelSelector.call(
      turn: probe_turn,
      selector_source: selector_source,
      selector: selector
    )
  end
end
