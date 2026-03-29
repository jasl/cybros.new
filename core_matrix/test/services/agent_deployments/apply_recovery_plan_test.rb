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

  test "does not apply a resume with rebind plan after the replacement deployment stops being schedulable" do
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
    plan = AgentDeployments::BuildRecoveryPlan.call(
      deployment: replacement,
      workflow_run: context[:workflow_run]
    )
    replacement.update!(health_status: "offline", unavailability_reason: "runtime_offline")

    applied = AgentDeployments::ApplyRecoveryPlan.call(
      deployment: replacement,
      workflow_run: context[:workflow_run],
      recovery_plan: plan
    )

    refute applied
    assert context[:workflow_run].reload.waiting?
    assert_equal context[:agent_deployment], context[:conversation].reload.agent_deployment
    assert_equal context[:agent_deployment], context[:turn].reload.agent_deployment
  end

  test "applies a preplanned resume with rebind without re-resolving the selector at apply time" do
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
    plan = AgentDeployments::BuildRecoveryPlan.call(
      deployment: replacement,
      workflow_run: context[:workflow_run]
    )
    ProviderEntitlement.where(installation: context[:installation]).update_all(active: false)

    applied = AgentDeployments::ApplyRecoveryPlan.call(
      deployment: replacement,
      workflow_run: context[:workflow_run],
      recovery_plan: plan
    )

    assert applied
    assert_equal replacement, context[:conversation].reload.agent_deployment
    assert_equal replacement, context[:turn].reload.agent_deployment
  end

  test "applies a resume with rebind plan through the canonical rebinding owner without re-resolving the target" do
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
    original_resolve_call = nil
    recovery_target = AgentDeploymentRecoveryTarget.new(
      agent_deployment: replacement,
      resolved_model_selection_snapshot: resolved_snapshot_for(
        turn: context[:turn],
        agent_deployment: replacement,
        selector_source: "conversation",
        selector: context[:turn].recovery_selector
      ),
      selector_source: "conversation",
      rebind_turn: true
    )
    plan = AgentDeploymentRecoveryPlan.new(
      action: "resume_with_rebind",
      recovery_target: recovery_target
    )
    original_resolve_call = AgentDeployments::ResolveRecoveryTarget.method(:call)

    AgentDeployments::ResolveRecoveryTarget.singleton_class.define_method(:call) do |*args, **kwargs|
      flunk("ApplyRecoveryPlan must reuse the recovery target from the planner instead of re-resolving it")
    end

    applied = AgentDeployments::ApplyRecoveryPlan.call(
      deployment: replacement,
      workflow_run: context[:workflow_run],
      recovery_plan: plan
    )

    assert applied
    assert_equal replacement, context[:conversation].reload.agent_deployment
    assert_equal replacement, context[:turn].reload.agent_deployment
    assert_equal replacement.public_id, context[:turn].reload.execution_snapshot.identity["agent_deployment_id"]
  ensure
    if original_resolve_call
      AgentDeployments::ResolveRecoveryTarget.singleton_class.define_method(:call, original_resolve_call)
    end
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
