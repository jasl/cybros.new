require "test_helper"

class ExecutionIdentityRecoveryPlanTest < ActiveSupport::TestCase
  test "exposes the canonical recovery target for a rebind recovery plan" do
    agent_definition_version = AgentDefinitionVersion.new(definition_fingerprint: "replacement-#{next_test_sequence}")
    recovery_target = ExecutionIdentityRecoveryTarget.new(
      agent_definition_version: agent_definition_version,
      resolved_model_selection_snapshot: { resolved_provider_handle: "dev" },
      selector_source: :conversation,
      rebind_turn: true
    )
    plan = ExecutionIdentityRecoveryPlan.new(
      action: "resume_with_rebind",
      recovery_target: recovery_target
    )

    assert plan.resume?
    assert plan.rebind_turn?
    refute plan.manual_recovery_required?
    assert_same recovery_target, plan.recovery_target
  end

  test "exposes manual recovery predicates" do
    plan = ExecutionIdentityRecoveryPlan.new(
      action: "manual_recovery_required",
      drift_reason: "capability_contract_drift"
    )

    refute plan.resume?
    refute plan.rebind_turn?
    assert plan.manual_recovery_required?
    assert_equal "capability_contract_drift", plan.drift_reason
    assert_nil plan.recovery_target
  end
end
