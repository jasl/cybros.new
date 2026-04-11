require "test_helper"

class AgentSnapshots::BuildRecoveryPlanTest < ActiveSupport::TestCase
  test "returns resume when runtime identity still matches" do
    context = build_waiting_recovery_context!

    plan = AgentSnapshots::BuildRecoveryPlan.call(
      agent_snapshot: context[:agent_snapshot],
      workflow_run: context[:workflow_run]
    )

    assert_equal "resume", plan.action
    assert_nil plan.drift_reason
  end

  test "returns manual recovery required for capability contract drift" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_agent_snapshot!(
      installation: context[:installation],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    drifted_snapshot = create_capability_snapshot!(
      agent_snapshot: replacement,
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    AgentConnection.where(agent: context[:agent], lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_agent_connection!(
      installation: context[:installation],
      agent: context[:agent],
      agent_snapshot: drifted_snapshot,
      health_status: "healthy",
      auto_resume_eligible: true,
      last_heartbeat_at: Time.current,
      last_health_check_at: Time.current
    )

    plan = AgentSnapshots::BuildRecoveryPlan.call(
      agent_snapshot: drifted_snapshot,
      workflow_run: context[:workflow_run]
    )

    assert_equal "manual_recovery_required", plan.action
    assert_equal "capability_contract_drift", plan.drift_reason
  end

  test "returns resume with rebind for a compatible rotated replacement" do
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

    assert_equal "resume_with_rebind", plan.action
    assert plan.rebind_turn?
    assert_instance_of AgentSnapshotRecoveryTarget, plan.recovery_target
    assert_equal replacement, plan.recovery_target.agent_snapshot
    assert_equal context[:turn].recovery_selector, plan.recovery_target.resolved_model_selection_snapshot["normalized_selector"]
  end

  test "returns manual recovery required when a rotated replacement drifts in profile policy" do
    context = build_profile_aware_waiting_recovery_context!
    replacement = create_profile_aware_replacement_agent_snapshot!(
      installation: context[:installation],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime],
      profile_catalog: default_profile_catalog.deep_merge(
        "main" => { "allowed_tool_names" => %w[exec_command] }
      )
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

    assert_equal "manual_recovery_required", plan.action
    assert_equal "capability_contract_drift", plan.drift_reason
  end

  private

  def build_profile_aware_waiting_recovery_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    capability_snapshot = create_capability_snapshot!(
      agent_snapshot: context[:agent_snapshot],
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    adopt_agent_snapshot!(context, capability_snapshot, turn: nil)
    context[:agent_connection].update!(auto_resume_eligible: true)

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Recovery input",
      agent_snapshot: context[:agent_snapshot],
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

    AgentSnapshots::MarkUnavailable.call(
      agent_snapshot: context[:agent_snapshot],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    context.merge(
      conversation: conversation,
      turn: turn.reload,
      workflow_run: workflow_run.reload
    )
  end

  def create_profile_aware_replacement_agent_snapshot!(
    installation:,
    agent:,
    execution_runtime:,
    profile_catalog:
  )
    agent_snapshot = create_compatible_replacement_agent_snapshot!(
      installation: installation,
      agent: agent,
      execution_runtime: execution_runtime
    )
    capability_snapshot = create_capability_snapshot!(
      agent_snapshot: agent_snapshot,
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
      profile_catalog: profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    agent = agent_snapshot.agent
    AgentConnection.where(agent: agent, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_agent_connection!(
      installation: installation,
      agent: agent,
      agent_snapshot: capability_snapshot,
      health_status: "offline",
      auto_resume_eligible: true,
      last_heartbeat_at: Time.current,
      last_health_check_at: Time.current
    )
    capability_snapshot
  end
end
