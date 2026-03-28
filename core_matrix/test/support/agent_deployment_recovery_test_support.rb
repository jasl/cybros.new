module AgentDeploymentRecoveryTestSupport
  def build_recovery_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
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

    context.merge(conversation: conversation, turn: turn.reload, workflow_run: workflow_run.reload)
  end

  def build_waiting_recovery_context!
    context = build_recovery_context!
    context[:agent_deployment].update!(auto_resume_eligible: true)

    AgentDeployments::MarkUnavailable.call(
      deployment: context[:agent_deployment],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    context.merge(workflow_run: context[:workflow_run].reload)
  end

  def build_waiting_human_interaction_recovery_context!
    context = build_human_interaction_context!
    context[:agent_deployment].update!(auto_resume_eligible: true)
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )

    AgentDeployments::MarkUnavailable.call(
      deployment: context[:agent_deployment],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    context.merge(request: request, workflow_run: context[:workflow_run].reload)
  end

  def create_compatible_replacement_deployment!(
    installation:,
    agent_installation:,
    execution_environment: create_execution_environment!(installation: installation)
  )
    active_snapshot = agent_installation
      .agent_deployments
      .find_by(bootstrap_state: "active")
      &.active_capability_snapshot
    deployment = create_agent_deployment!(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: execution_environment,
      fingerprint: "replacement-#{next_test_sequence}",
      health_status: "offline",
      bootstrap_state: "pending",
      auto_resume_eligible: true
    )
    capability_snapshot = create_capability_snapshot!(
      agent_deployment: deployment,
      version: 1,
      protocol_methods: active_snapshot&.protocol_methods || default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: active_snapshot&.tool_catalog || default_tool_catalog("shell_exec", "workspace_variables_get"),
      profile_catalog: active_snapshot&.profile_catalog || {},
      config_schema_snapshot: active_snapshot&.config_schema_snapshot || default_config_schema_snapshot(include_selector_slots: true),
      conversation_override_schema_snapshot: active_snapshot&.conversation_override_schema_snapshot || {},
      default_config_snapshot: active_snapshot&.default_config_snapshot || default_default_config_snapshot(include_selector_slots: true)
    )
    deployment.update!(active_capability_snapshot: capability_snapshot)
    deployment
  end
end

ActiveSupport::TestCase.include(AgentDeploymentRecoveryTestSupport)
