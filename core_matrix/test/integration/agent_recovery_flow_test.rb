require "test_helper"

class AgentRecoveryFlowTest < ActionDispatch::IntegrationTest
  test "drifted outage recovery requires an explicit retry before work continues" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent_program: context[:agent_program]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Recover this workflow",
      executor_program: context[:executor_program],
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

    AgentProgramVersions::MarkUnavailable.call(
      deployment: context[:agent_program_version],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    drifted_snapshot = create_capability_snapshot!(
      agent_program_version: context[:agent_program_version],
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    adopt_agent_program_version!(context, drifted_snapshot, turn: nil)
    AgentProgramVersions::RecordHeartbeat.call(
      deployment: context[:agent_program_version],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    assert_equal [], AgentProgramVersions::AutoResumeWorkflows.call(deployment: context[:agent_program_version])

    replacement = create_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      executor_program: context[:executor_program]
    )
    retried = Workflows::ManualRetry.call(
      workflow_run: workflow_run.reload,
      deployment: replacement,
      actor: create_user!(installation: context[:installation], role: "admin"),
      selector: "role:planner"
    )

    assert workflow_run.reload.canceled?
    assert_equal "manual_recovery_required", workflow_run.wait_reason_kind
    assert retried.active?
    assert_equal context[:agent_program], conversation.reload.agent_program
    assert_equal replacement, retried.turn.agent_program_version
    assert_equal "role:planner", retried.turn.normalized_selector
    assert_equal "openai", retried.turn.resolved_provider_handle
    assert_equal "gpt-5.4", retried.turn.resolved_model_ref
    assert_equal replacement.public_id, retried.turn.execution_snapshot.identity["agent_program_version_id"]
    assert_equal replacement.public_id, retried.execution_identity["agent_program_version_id"]
    assert_equal context[:executor_program].public_id, retried.execution_identity["executor_program_id"]
    assert_equal(
      %w[agent_program_version.degraded agent_program_version.paused_agent_unavailable workflow.manual_retried],
      AuditLog.where(installation: context[:installation]).order(:created_at).pluck(:action).last(3)
    )
  end

  private

  def create_replacement_deployment!(
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
