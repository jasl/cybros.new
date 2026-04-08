require "test_helper"

class AgentProgramVersions::ResolveRecoveryTargetTest < ActiveSupport::TestCase
  test "returns the canonical paused-work recovery target for a compatible rotated replacement" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      executor_program: context[:executor_program]
    )

    recovery_target = AgentProgramVersions::ResolveRecoveryTarget.call(
      conversation: context[:conversation],
      turn: context[:turn],
      agent_program_version: replacement,
      selector_source: "conversation",
      selector: context[:turn].recovery_selector,
      require_auto_resume_eligible: true,
      rebind_turn: true
    )

    assert_instance_of AgentProgramVersionRecoveryTarget, recovery_target
    assert_equal replacement, recovery_target.agent_program_version
    assert_equal "conversation", recovery_target.selector_source
    assert_equal context[:turn].recovery_selector, recovery_target.resolved_model_selection_snapshot["normalized_selector"]
    assert recovery_target.rebind_turn?
  end

  test "rejects a replacement from another logical agent when paused-work continuity is required" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: create_agent_program!(installation: context[:installation]),
      executor_program: context[:executor_program]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      AgentProgramVersions::ResolveRecoveryTarget.call(
        conversation: context[:conversation],
        turn: context[:turn],
        agent_program_version: replacement,
        selector_source: "conversation",
        selector: context[:turn].recovery_selector,
        rebind_turn: true
      )
    end

    assert_same context[:turn], error.record
    assert_includes error.record.errors[:agent_program_version], "must belong to the same agent program"
  end

  private

  def build_paused_recovery_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    richer_snapshot = create_capability_snapshot!(
      agent_program_version: context[:agent_program_version],
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    adopt_agent_program_version!(context, richer_snapshot, turn: nil)
    context[:agent_session].update!(auto_resume_eligible: true)

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent_program: context[:agent_program]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Paused recovery input",
      executor_program: context[:executor_program],
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
    agent_program:,
    executor_program: create_executor_program!(installation: installation)
  )
    AgentSession.where(agent_program: agent_program, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    deployment = create_agent_program_version!(
      installation: installation,
      agent_program: agent_program,
      fingerprint: "replacement-#{next_test_sequence}",
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    agent_program.update!(default_executor_program: executor_program)
    create_agent_session!(
      installation: installation,
      agent_program: agent_program,
      agent_program_version: deployment,
      health_status: "healthy",
      auto_resume_eligible: true,
      last_heartbeat_at: Time.current,
      last_health_check_at: Time.current
    )
    ExecutorSession.where(executor_program: executor_program, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_executor_session!(
      installation: installation,
      executor_program: executor_program,
      last_heartbeat_at: Time.current
    )

    deployment
  end
end
