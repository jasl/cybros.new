require "test_helper"

class AgentRecoveryFlowTest < ActionDispatch::IntegrationTest
  test "drifted outage recovery requires an explicit retry before work continues" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Recover this workflow",
      execution_runtime: context[:execution_runtime],
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

    drifted_snapshot = create_capability_snapshot!(
      agent_snapshot: context[:agent_snapshot],
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    adopt_agent_snapshot!(context, drifted_snapshot, turn: nil)
    AgentSnapshots::RecordHeartbeat.call(
      agent_snapshot: context[:agent_snapshot],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    assert_equal [], AgentSnapshots::AutoResumeWorkflows.call(agent_snapshot: context[:agent_snapshot])

    replacement = create_replacement_agent_snapshot!(
      installation: context[:installation],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    retried = Workflows::ManualRetry.call(
      workflow_run: workflow_run.reload,
      agent_snapshot: replacement,
      actor: create_user!(installation: context[:installation], role: "admin"),
      selector: "role:planner"
    )

    assert workflow_run.reload.canceled?
    assert_equal "manual_recovery_required", workflow_run.wait_reason_kind
    assert retried.active?
    assert_equal context[:agent], conversation.reload.agent
    assert_equal replacement, retried.turn.agent_snapshot
    assert_equal "role:planner", retried.turn.normalized_selector
    assert_equal "openai", retried.turn.resolved_provider_handle
    assert_equal "gpt-5.4", retried.turn.resolved_model_ref
    assert_equal replacement.public_id, retried.turn.execution_snapshot.identity["agent_snapshot_id"]
    assert_equal replacement.public_id, retried.execution_identity["agent_snapshot_id"]
    assert_equal context[:execution_runtime].public_id, retried.execution_identity["execution_runtime_id"]
    assert_equal(
      %w[agent_snapshot.degraded agent_snapshot.paused_agent_unavailable workflow.manual_retried],
      AuditLog.where(installation: context[:installation]).order(:created_at).pluck(:action).last(3)
    )
  end

  private

  def create_replacement_agent_snapshot!(
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
