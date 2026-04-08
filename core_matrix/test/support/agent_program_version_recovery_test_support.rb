module AgentProgramVersionRecoveryTestSupport
  def build_recovery_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Recovery input",
      agent_program_version: context[:agent_program_version],
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
    context[:agent_session].update!(auto_resume_eligible: true)

    AgentProgramVersions::MarkUnavailable.call(
      deployment: context[:agent_program_version],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    context.merge(workflow_run: context[:workflow_run].reload)
  end

  def build_waiting_human_interaction_recovery_context!
    context = build_human_interaction_context!
    context[:agent_session].update!(auto_resume_eligible: true)
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )

    AgentProgramVersions::MarkUnavailable.call(
      deployment: context[:agent_program_version],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    context.merge(request: request, workflow_run: context[:workflow_run].reload)
  end

  def create_compatible_replacement_deployment!(
    installation:,
    agent_program:,
    executor_program: create_executor_program!(installation: installation)
  )
    active_snapshot = agent_program.current_agent_program_version
    deployment = create_agent_program_version!(
      installation: installation,
      agent_program: agent_program,
      fingerprint: "replacement-#{next_test_sequence}",
      protocol_methods: active_snapshot&.protocol_methods || default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: active_snapshot&.tool_catalog || default_tool_catalog("exec_command", "workspace_variables_get"),
      profile_catalog: active_snapshot&.profile_catalog || {},
      config_schema_snapshot: active_snapshot&.config_schema_snapshot || default_config_schema_snapshot(include_selector_slots: true),
      conversation_override_schema_snapshot: active_snapshot&.conversation_override_schema_snapshot || {},
      default_config_snapshot: active_snapshot&.default_config_snapshot || default_default_config_snapshot(include_selector_slots: true)
    )
    agent_program.update!(default_executor_program: executor_program)
    AgentSession.where(agent_program: agent_program, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_agent_session!(
      installation: installation,
      agent_program: agent_program,
      agent_program_version: deployment,
      health_status: "offline",
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

ActiveSupport::TestCase.include(AgentProgramVersionRecoveryTestSupport)
