require "test_helper"

class AgentSnapshots::ApplyRecoveryPlanTest < ActiveSupport::TestCase
  test "applies a resume plan by restoring ready state" do
    context = build_waiting_recovery_context!
    plan = AgentSnapshotRecoveryPlan.new(action: "resume")

    applied = AgentSnapshots::ApplyRecoveryPlan.call(
      agent_snapshot: context[:agent_snapshot],
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
    plan = AgentSnapshotRecoveryPlan.new(
      action: "manual_recovery_required",
      drift_reason: "capability_contract_drift"
    )

    applied = AgentSnapshots::ApplyRecoveryPlan.call(
      agent_snapshot: context[:agent_snapshot],
      workflow_run: context[:workflow_run],
      recovery_plan: plan
    )

    refute applied

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "manual_recovery_required", workflow_run.wait_reason_kind
    assert_equal "paused_agent_unavailable", workflow_run.recovery_state
    assert_equal "capability_contract_drift", workflow_run.recovery_drift_reason
  end

  test "does not apply a resume with rebind plan after the replacement agent_snapshot stops being schedulable" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_agent_snapshot!(
      installation: context[:installation],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    AgentSnapshots::RecordHeartbeat.call(
      agent_snapshot: replacement,
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )
    plan = AgentSnapshots::BuildRecoveryPlan.call(
      agent_snapshot: replacement,
      workflow_run: context[:workflow_run]
    )
    replacement.active_agent_connection.update!(
      health_status: "offline",
      auto_resume_eligible: false,
      unavailability_reason: "runtime_offline",
      last_health_check_at: Time.current
    )

    applied = AgentSnapshots::ApplyRecoveryPlan.call(
      agent_snapshot: replacement,
      workflow_run: context[:workflow_run],
      recovery_plan: plan
    )

    refute applied
    assert context[:workflow_run].reload.waiting?
    assert_equal context[:agent], context[:conversation].reload.agent
    assert_equal context[:agent_snapshot], context[:turn].reload.agent_snapshot
  end

  test "applies a preplanned resume with rebind without re-resolving the selector at apply time" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_agent_snapshot!(
      installation: context[:installation],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    AgentSnapshots::RecordHeartbeat.call(
      agent_snapshot: replacement,
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )
    plan = AgentSnapshots::BuildRecoveryPlan.call(
      agent_snapshot: replacement,
      workflow_run: context[:workflow_run]
    )
    ProviderEntitlement.where(installation: context[:installation]).update_all(active: false)

    applied = AgentSnapshots::ApplyRecoveryPlan.call(
      agent_snapshot: replacement,
      workflow_run: context[:workflow_run],
      recovery_plan: plan
    )

    assert applied
    assert_equal context[:agent], context[:conversation].reload.agent
    assert_equal replacement, context[:turn].reload.agent_snapshot
  end

  test "applies a resume with rebind plan through the canonical rebinding owner without re-resolving the target" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_agent_snapshot!(
      installation: context[:installation],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    AgentSnapshots::RecordHeartbeat.call(
      agent_snapshot: replacement,
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )
    original_resolve_call = nil
    recovery_target = AgentSnapshotRecoveryTarget.new(
      agent_snapshot: replacement,
      resolved_model_selection_snapshot: resolved_snapshot_for(
        turn: context[:turn],
        agent_snapshot: replacement,
        selector_source: "conversation",
        selector: context[:turn].recovery_selector
      ),
      selector_source: "conversation",
      rebind_turn: true
    )
    plan = AgentSnapshotRecoveryPlan.new(
      action: "resume_with_rebind",
      recovery_target: recovery_target
    )
    original_resolve_call = AgentSnapshots::ResolveRecoveryTarget.method(:call)

    AgentSnapshots::ResolveRecoveryTarget.singleton_class.define_method(:call) do |*args, **kwargs|
      flunk("ApplyRecoveryPlan must reuse the recovery target from the planner instead of re-resolving it")
    end

    applied = AgentSnapshots::ApplyRecoveryPlan.call(
      agent_snapshot: replacement,
      workflow_run: context[:workflow_run],
      recovery_plan: plan
    )

    assert applied
    assert_equal context[:agent], context[:conversation].reload.agent
    assert_equal replacement, context[:turn].reload.agent_snapshot
    assert_equal replacement.public_id, context[:turn].reload.execution_snapshot.identity["agent_snapshot_id"]
  ensure
    if original_resolve_call
      AgentSnapshots::ResolveRecoveryTarget.singleton_class.define_method(:call, original_resolve_call)
    end
  end

  private

  def resolved_snapshot_for(turn:, agent_snapshot:, selector_source:, selector:)
    probe_turn = turn.dup
    probe_turn.installation = turn.installation
    probe_turn.conversation = turn.conversation
    probe_turn.agent_snapshot = agent_snapshot
    probe_turn.pinned_agent_snapshot_fingerprint = agent_snapshot.fingerprint
    probe_turn.resolved_config_snapshot = turn.resolved_config_snapshot.deep_dup
    probe_turn.resolved_model_selection_snapshot = turn.resolved_model_selection_snapshot.deep_dup

    Workflows::ResolveModelSelector.call(
      turn: probe_turn,
      selector_source: selector_source,
      selector: selector
    )
  end
end
