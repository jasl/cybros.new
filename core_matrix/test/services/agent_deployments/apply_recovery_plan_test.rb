require "test_helper"

class AgentDeployments::ApplyRecoveryPlanTest < ActiveSupport::TestCase
  test "applies a resume plan by restoring ready state" do
    context = build_waiting_recovery_context!
    plan = AgentDeploymentRecoveryPlan.new(action: "resume")

    applied = AgentDeployments::ApplyRecoveryPlan.call(
      deployment: context[:agent_deployment],
      workflow_run: context[:workflow_run],
      recovery_plan: plan
    )

    assert applied

    workflow_run = context[:workflow_run].reload
    assert workflow_run.ready?
    assert_nil workflow_run.wait_reason_kind
    assert_equal({}, workflow_run.wait_reason_payload)
  end

  test "applies a manual recovery plan by preserving the paused unavailable state and drift reason" do
    context = build_waiting_recovery_context!
    plan = AgentDeploymentRecoveryPlan.new(
      action: "manual_recovery_required",
      drift_reason: "capability_snapshot_version_drift"
    )

    applied = AgentDeployments::ApplyRecoveryPlan.call(
      deployment: context[:agent_deployment],
      workflow_run: context[:workflow_run],
      recovery_plan: plan
    )

    refute applied

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "manual_recovery_required", workflow_run.wait_reason_kind
    assert_equal "paused_agent_unavailable", workflow_run.wait_reason_payload["recovery_state"]
    assert_equal "capability_snapshot_version_drift", workflow_run.wait_reason_payload["drift_reason"]
  end
end
