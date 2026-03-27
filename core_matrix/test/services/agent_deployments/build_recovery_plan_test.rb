require "test_helper"

class AgentDeployments::BuildRecoveryPlanTest < ActiveSupport::TestCase
  test "returns resume when runtime identity still matches" do
    context = build_waiting_recovery_context!

    plan = AgentDeployments::BuildRecoveryPlan.call(
      deployment: context[:agent_deployment],
      workflow_run: context[:workflow_run]
    )

    assert_equal "resume", plan.action
    assert_nil plan.drift_reason
  end

  test "returns manual recovery required for capability drift" do
    context = build_waiting_recovery_context!
    drifted_snapshot = create_capability_snapshot!(
      agent_deployment: context[:agent_deployment],
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("shell_exec", "workspace_variables_get"),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    context[:agent_deployment].update!(active_capability_snapshot: drifted_snapshot)

    plan = AgentDeployments::BuildRecoveryPlan.call(
      deployment: context[:agent_deployment],
      workflow_run: context[:workflow_run]
    )

    assert_equal "manual_recovery_required", plan.action
    assert_equal "capability_snapshot_version_drift", plan.drift_reason
  end

  test "returns resume with rebind for a compatible rotated replacement" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation],
      execution_environment: context[:execution_environment]
    )

    plan = AgentDeployments::BuildRecoveryPlan.call(
      deployment: replacement,
      workflow_run: context[:workflow_run]
    )

    assert_equal "resume_with_rebind", plan.action
    assert plan.rebind_turn?
    assert_equal replacement.fingerprint, plan.resolved_model_selection_snapshot["deployment_fingerprint"]
  end
end
