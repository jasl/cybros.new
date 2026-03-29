require "test_helper"

class AgentDeployments::ResolveRecoveryTargetTest < ActiveSupport::TestCase
  test "returns the canonical paused-work recovery target for a compatible rotated replacement" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation],
      execution_environment: context[:execution_environment]
    )

    recovery_target = AgentDeployments::ResolveRecoveryTarget.call(
      conversation: context[:conversation],
      turn: context[:turn],
      agent_deployment: replacement,
      selector_source: "conversation",
      selector: context[:turn].recovery_selector,
      require_auto_resume_eligible: true,
      rebind_turn: true
    )

    assert_instance_of AgentDeploymentRecoveryTarget, recovery_target
    assert_equal replacement, recovery_target.agent_deployment
    assert_equal "conversation", recovery_target.selector_source
    assert_equal context[:turn].recovery_selector, recovery_target.resolved_model_selection_snapshot["normalized_selector"]
    assert recovery_target.rebind_turn?
  end

  test "rejects a replacement from another logical agent when paused-work continuity is required" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_installation: create_agent_installation!(installation: context[:installation]),
      execution_environment: context[:execution_environment]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      AgentDeployments::ResolveRecoveryTarget.call(
        conversation: context[:conversation],
        turn: context[:turn],
        agent_deployment: replacement,
        selector_source: "conversation",
        selector: context[:turn].recovery_selector,
        rebind_turn: true
      )
    end

    assert_same context[:turn], error.record
    assert_includes error.record.errors[:agent_deployment], "must belong to the same logical agent installation"
  end

  private

  def build_paused_recovery_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    richer_snapshot = create_capability_snapshot!(
      agent_deployment: context[:agent_deployment],
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("shell_exec", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    context[:agent_deployment].update!(
      active_capability_snapshot: richer_snapshot,
      auto_resume_eligible: true
    )

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Paused recovery input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {}
    )

    context.merge(conversation: conversation, turn: turn.reload)
  end

  def create_compatible_replacement_deployment!(
    installation:,
    agent_installation:,
    execution_environment: create_execution_environment!(installation: installation)
  )
    agent_installation.agent_deployments.where(bootstrap_state: "active").update_all(
      bootstrap_state: "superseded",
      updated_at: Time.current
    )
    deployment = create_agent_deployment!(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: execution_environment,
      fingerprint: "replacement-#{next_test_sequence}",
      health_status: "healthy",
      auto_resume_eligible: true
    )
    capability_snapshot = create_capability_snapshot!(
      agent_deployment: deployment,
      version: 1,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("shell_exec", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    deployment.update!(active_capability_snapshot: capability_snapshot)

    deployment
  end
end
