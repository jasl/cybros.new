require "test_helper"

class AgentDeploymentRecoveryPlanTest < ActiveSupport::TestCase
  test "exposes resume predicates for a rebind recovery plan" do
    plan = AgentDeploymentRecoveryPlan.new(
      action: "resume_with_rebind",
      resolved_model_selection_snapshot: { "resolved_provider_handle" => "dev" }
    )

    assert plan.resume?
    assert plan.rebind_turn?
    refute plan.manual_recovery_required?
  end

  test "exposes manual recovery predicates" do
    plan = AgentDeploymentRecoveryPlan.new(
      action: "manual_recovery_required",
      drift_reason: "capability_snapshot_version_drift"
    )

    refute plan.resume?
    refute plan.rebind_turn?
    assert plan.manual_recovery_required?
    assert_equal "capability_snapshot_version_drift", plan.drift_reason
  end
end
