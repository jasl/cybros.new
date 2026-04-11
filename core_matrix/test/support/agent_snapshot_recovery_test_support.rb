module AgentSnapshotRecoveryTestSupport
  def build_recovery_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
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

    context.merge(conversation: conversation, turn: turn.reload, workflow_run: workflow_run.reload)
  end

  def build_waiting_recovery_context!
    context = build_recovery_context!
    context[:agent_connection].update!(auto_resume_eligible: true)

    AgentSnapshots::MarkUnavailable.call(
      agent_snapshot: context[:agent_snapshot],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    context.merge(workflow_run: context[:workflow_run].reload)
  end

  def build_waiting_human_interaction_recovery_context!
    context = build_human_interaction_context!
    context[:agent_connection].update!(auto_resume_eligible: true)
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )

    AgentSnapshots::MarkUnavailable.call(
      agent_snapshot: context[:agent_snapshot],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    context.merge(request: request, workflow_run: context[:workflow_run].reload)
  end

  def create_compatible_replacement_agent_snapshot!(
    installation:,
    agent:,
    execution_runtime: create_execution_runtime!(installation: installation)
  )
    active_snapshot = agent.current_agent_snapshot
    agent_snapshot = create_agent_snapshot!(
      installation: installation,
      agent: agent,
      fingerprint: "replacement-#{next_test_sequence}",
      protocol_methods: active_snapshot&.protocol_methods || default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: active_snapshot&.tool_catalog || default_tool_catalog("exec_command", "workspace_variables_get"),
      profile_catalog: active_snapshot&.profile_catalog || {},
      config_schema_snapshot: active_snapshot&.config_schema_snapshot || default_config_schema_snapshot(include_selector_slots: true),
      conversation_override_schema_snapshot: active_snapshot&.conversation_override_schema_snapshot || {},
      default_config_snapshot: active_snapshot&.default_config_snapshot || default_default_config_snapshot(include_selector_slots: true)
    )
    agent.update!(default_execution_runtime: execution_runtime)
    AgentConnection.where(agent: agent, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_agent_connection!(
      installation: installation,
      agent: agent,
      agent_snapshot: agent_snapshot,
      health_status: "offline",
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

ActiveSupport::TestCase.include(AgentSnapshotRecoveryTestSupport)
