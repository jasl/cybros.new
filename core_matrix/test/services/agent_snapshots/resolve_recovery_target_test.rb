require "test_helper"

class AgentSnapshots::ResolveRecoveryTargetTest < ActiveSupport::TestCase
  test "returns the canonical paused-work recovery target for a compatible rotated replacement" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_agent_snapshot!(
      installation: context[:installation],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )

    recovery_target = AgentSnapshots::ResolveRecoveryTarget.call(
      conversation: context[:conversation],
      turn: context[:turn],
      agent_snapshot: replacement,
      selector_source: "conversation",
      selector: context[:turn].recovery_selector,
      require_auto_resume_eligible: true,
      rebind_turn: true
    )

    assert_instance_of AgentSnapshotRecoveryTarget, recovery_target
    assert_equal replacement, recovery_target.agent_snapshot
    assert_equal "conversation", recovery_target.selector_source
    assert_equal context[:turn].recovery_selector, recovery_target.resolved_model_selection_snapshot["normalized_selector"]
    assert recovery_target.rebind_turn?
  end

  test "rejects a replacement from another logical agent when paused-work continuity is required" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_agent_snapshot!(
      installation: context[:installation],
      agent: create_agent!(installation: context[:installation]),
      execution_runtime: context[:execution_runtime]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      AgentSnapshots::ResolveRecoveryTarget.call(
        conversation: context[:conversation],
        turn: context[:turn],
        agent_snapshot: replacement,
        selector_source: "conversation",
        selector: context[:turn].recovery_selector,
        rebind_turn: true
      )
    end

    assert_same context[:turn], error.record
    assert_includes error.record.errors[:agent_snapshot], "must belong to the same agent"
  end

  private

  def build_paused_recovery_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    richer_snapshot = create_capability_snapshot!(
      agent_snapshot: context[:agent_snapshot],
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    adopt_agent_snapshot!(context, richer_snapshot, turn: nil)
    context[:agent_connection].update!(auto_resume_eligible: true)

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Paused recovery input",
      execution_runtime: context[:execution_runtime],
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

  def create_compatible_replacement_agent_snapshot!(
    installation:,
    agent:,
    execution_runtime: create_execution_runtime!(installation: installation)
  )
    AgentConnection.where(agent: agent, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    agent_snapshot = create_agent_snapshot!(
      installation: installation,
      agent: agent,
      fingerprint: "replacement-#{next_test_sequence}",
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    agent.update!(default_execution_runtime: execution_runtime)
    create_agent_connection!(
      installation: installation,
      agent: agent,
      agent_snapshot: agent_snapshot,
      health_status: "healthy",
      auto_resume_eligible: true,
      last_heartbeat_at: Time.current,
      last_health_check_at: Time.current
    )
    ExecutionRuntimeConnection.where(execution_runtime: execution_runtime, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_execution_runtime_connection!(
      installation: installation,
      execution_runtime: execution_runtime,
      last_heartbeat_at: Time.current
    )

    agent_snapshot
  end
end
