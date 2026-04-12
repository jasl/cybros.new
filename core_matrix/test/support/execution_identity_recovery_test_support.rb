module ExecutionIdentityRecoveryTestSupport
  def build_recovery_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Recovery input",
      agent_definition_version: context[:agent_definition_version],
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

    AgentDefinitionVersions::MarkUnavailable.call(
      agent_definition_version: context[:agent_definition_version],
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

    AgentDefinitionVersions::MarkUnavailable.call(
      agent_definition_version: context[:agent_definition_version],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    context.merge(request: request, workflow_run: context[:workflow_run].reload)
  end

  def create_compatible_replacement_agent_definition_version!(
    installation:,
    agent:,
    execution_runtime: create_execution_runtime!(installation: installation)
  )
    current_agent_definition_version = agent.current_agent_definition_version
    agent_definition_version = create_agent_definition_version!(
      installation: installation,
      agent: agent,
      fingerprint: "replacement-#{next_test_sequence}",
      protocol_methods: current_agent_definition_version&.protocol_methods || default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_contract: current_agent_definition_version&.tool_contract || default_tool_catalog("exec_command", "workspace_variables_get"),
      profile_policy: current_agent_definition_version&.profile_policy || {},
      canonical_config_schema: current_agent_definition_version&.canonical_config_schema || default_canonical_config_schema(include_selector_slots: true),
      conversation_override_schema: current_agent_definition_version&.conversation_override_schema || {},
      default_canonical_config: current_agent_definition_version&.default_canonical_config || default_default_canonical_config(include_selector_slots: true)
    )
    agent.update!(default_execution_runtime: execution_runtime)
    AgentConnection.where(agent: agent, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_agent_connection!(
      installation: installation,
      agent: agent,
      agent_definition_version: agent_definition_version,
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
    agent_definition_version
  end
end

ActiveSupport::TestCase.include(ExecutionIdentityRecoveryTestSupport)
