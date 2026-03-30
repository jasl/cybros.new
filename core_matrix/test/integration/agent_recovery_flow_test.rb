require "test_helper"

class AgentRecoveryFlowTest < ActionDispatch::IntegrationTest
  test "drifted outage recovery requires an explicit retry before work continues" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Recover this workflow",
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

    drifted_snapshot = create_capability_snapshot!(
      agent_deployment: context[:agent_deployment],
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    context[:agent_deployment].update!(active_capability_snapshot: drifted_snapshot)
    AgentDeployments::RecordHeartbeat.call(
      deployment: context[:agent_deployment],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    assert_equal [], AgentDeployments::AutoResumeWorkflows.call(deployment: context[:agent_deployment])

    replacement = create_replacement_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation],
      execution_environment: context[:execution_environment]
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
    assert_equal replacement, conversation.reload.agent_deployment
    assert_equal replacement, retried.turn.agent_deployment
    assert_equal "role:planner", retried.turn.normalized_selector
    assert_equal "openai", retried.turn.resolved_provider_handle
    assert_equal "gpt-5.4", retried.turn.resolved_model_ref
    assert_equal replacement.public_id, retried.turn.execution_snapshot.identity["agent_deployment_id"]
    assert_equal replacement.public_id, retried.execution_identity["agent_deployment_id"]
    assert_equal context[:execution_environment].public_id, retried.execution_identity["execution_environment_id"]
    assert_equal(
      %w[agent_deployment.degraded agent_deployment.paused_agent_unavailable workflow.manual_retried],
      AuditLog.where(installation: context[:installation]).order(:created_at).pluck(:action).last(3)
    )
  end

  private

  def create_replacement_deployment!(
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
      tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    deployment.update!(active_capability_snapshot: capability_snapshot)
    deployment
  end
end
