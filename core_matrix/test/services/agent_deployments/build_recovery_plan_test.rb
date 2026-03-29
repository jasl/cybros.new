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

    assert_equal "resume_with_rebind", plan.action
    assert plan.rebind_turn?
    assert_instance_of AgentDeploymentRecoveryTarget, plan.recovery_target
    assert_equal replacement, plan.recovery_target.agent_deployment
    assert_equal context[:turn].recovery_selector, plan.recovery_target.resolved_model_selection_snapshot["normalized_selector"]
  end

  test "returns manual recovery required when a rotated replacement drifts in profile policy" do
    context = build_profile_aware_waiting_recovery_context!
    replacement = create_profile_aware_replacement_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation],
      execution_environment: context[:execution_environment],
      profile_catalog: default_profile_catalog.deep_merge(
        "researcher" => { "allowed_tool_names" => %w[shell_exec] }
      )
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

    assert_equal "manual_recovery_required", plan.action
    assert_equal "capability_contract_drift", plan.drift_reason
  end

  private

  def build_profile_aware_waiting_recovery_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    capability_snapshot = create_capability_snapshot!(
      agent_deployment: context[:agent_deployment],
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("shell_exec", "workspace_variables_get"),
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    context[:agent_deployment].update!(active_capability_snapshot: capability_snapshot, auto_resume_eligible: true)

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Recovery input",
      agent_deployment: context[:agent_deployment],
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

    AgentDeployments::MarkUnavailable.call(
      deployment: context[:agent_deployment],
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

  def create_profile_aware_replacement_deployment!(
    installation:,
    agent_installation:,
    execution_environment:,
    profile_catalog:
  )
    deployment = create_compatible_replacement_deployment!(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: execution_environment
    )
    capability_snapshot = create_capability_snapshot!(
      agent_deployment: deployment,
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("shell_exec", "workspace_variables_get"),
      profile_catalog: profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    deployment.update!(active_capability_snapshot: capability_snapshot)
    deployment
  end
end
