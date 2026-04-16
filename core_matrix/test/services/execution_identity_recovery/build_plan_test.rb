require "test_helper"

class ExecutionIdentityRecovery::BuildPlanTest < ActiveSupport::TestCase
  test "returns resume when runtime identity still matches" do
    context = build_waiting_recovery_context!

    plan = ExecutionIdentityRecovery::BuildPlan.call(
      agent_definition_version: context[:agent_definition_version],
      workflow_run: context[:workflow_run]
    )

    assert_equal "resume", plan.action
    assert_nil plan.drift_reason
  end

  test "returns manual recovery required for capability contract drift" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    drifted_snapshot = create_compatible_agent_definition_version!(
      agent_definition_version: replacement,
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_contract: default_tool_catalog("exec_command", "workspace_variables_get"),
      default_canonical_config: default_default_canonical_config(include_selector_slots: true)
    )
    AgentConnection.where(agent: context[:agent], lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_agent_connection!(
      installation: context[:installation],
      agent: context[:agent],
      agent_definition_version: drifted_snapshot,
      health_status: "healthy",
      auto_resume_eligible: true,
      last_heartbeat_at: Time.current,
      last_health_check_at: Time.current
    )

    plan = ExecutionIdentityRecovery::BuildPlan.call(
      agent_definition_version: drifted_snapshot,
      workflow_run: context[:workflow_run]
    )

    assert_equal "manual_recovery_required", plan.action
    assert_equal "capability_contract_drift", plan.drift_reason
  end

  test "returns resume with rebind for a compatible rotated replacement" do
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

    plan = ExecutionIdentityRecovery::BuildPlan.call(
      agent_definition_version: replacement,
      workflow_run: context[:workflow_run]
    )

    assert_equal "resume_with_rebind", plan.action
    assert plan.rebind_turn?
    assert_instance_of ExecutionIdentityRecoveryTarget, plan.recovery_target
    assert_equal replacement, plan.recovery_target.agent_definition_version
    assert_equal context[:turn].recovery_selector, plan.recovery_target.resolved_model_selection_snapshot["normalized_selector"]
  end

  test "returns resume with rebind when a rotated replacement only changes agent-owned workspace settings metadata" do
    context = build_profile_aware_waiting_recovery_context!
    replacement = create_profile_aware_replacement_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime],
      default_workspace_agent_settings: default_workspace_agent_settings_payload.deep_merge(
        "interactive" => { "profile_key" => "friendly" }
      )
    )
    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: replacement,
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    plan = ExecutionIdentityRecovery::BuildPlan.call(
      agent_definition_version: replacement,
      workflow_run: context[:workflow_run]
    )

    assert_equal "resume_with_rebind", plan.action
    assert_nil plan.drift_reason
  end

  private

  def build_profile_aware_waiting_recovery_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    capability_snapshot = create_compatible_agent_definition_version!(
      agent_definition_version: context[:agent_definition_version],
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_contract: default_tool_catalog("exec_command", "workspace_variables_get"),
      canonical_config_schema: profile_aware_canonical_config_schema,
      conversation_override_schema: subagent_policy_conversation_override_schema,
      default_canonical_config: profile_aware_default_canonical_config
    )
    adopt_agent_definition_version!(context, capability_snapshot, turn: nil)
    context[:agent_connection].update!(auto_resume_eligible: true)

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Recovery input",
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

    AgentDefinitionVersions::MarkUnavailable.call(
      agent_definition_version: context[:agent_definition_version],
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

  def create_profile_aware_replacement_agent_definition_version!(
    installation:,
    agent:,
    execution_runtime:,
    default_workspace_agent_settings:
  )
    agent_definition_version = create_compatible_replacement_agent_definition_version!(
      installation: installation,
      agent: agent,
      execution_runtime: execution_runtime
    )
    capability_snapshot = create_compatible_agent_definition_version!(
      agent_definition_version: agent_definition_version,
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_contract: default_tool_catalog("exec_command", "workspace_variables_get"),
      canonical_config_schema: profile_aware_canonical_config_schema,
      conversation_override_schema: subagent_policy_conversation_override_schema,
      default_workspace_agent_settings: default_workspace_agent_settings,
      default_canonical_config: profile_aware_default_canonical_config
    )
    agent = agent_definition_version.agent
    AgentConnection.where(agent: agent, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_agent_connection!(
      installation: installation,
      agent: agent,
      agent_definition_version: capability_snapshot,
      health_status: "offline",
      auto_resume_eligible: true,
      last_heartbeat_at: Time.current,
      last_health_check_at: Time.current
    )
    capability_snapshot
  end
end
