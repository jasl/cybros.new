require "test_helper"

class AgentDeployments::AutoResumeWorkflowsTest < ActiveSupport::TestCase
  test "automatically resumes waiting workflows when runtime identity did not drift" do
    context = build_waiting_recovery_context!
    assert_equal context[:agent_deployment].public_id, context[:workflow_run].reload.blocking_resource_id

    AgentDeployments::RecordHeartbeat.call(
      deployment: context[:agent_deployment],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    resumed = AgentDeployments::AutoResumeWorkflows.call(deployment: context[:agent_deployment])

    assert_equal [context[:workflow_run].id], resumed.map(&:id)

    workflow_run = context[:workflow_run].reload
    assert workflow_run.ready?
    assert_nil workflow_run.wait_reason_kind
    assert_equal({}, workflow_run.wait_reason_payload)
    assert_nil workflow_run.blocking_resource_type
    assert_nil workflow_run.blocking_resource_id
  end

  test "requires explicit manual recovery when capabilities drift while waiting" do
    context = build_waiting_recovery_context!
    drifted_snapshot = create_capability_snapshot!(
      agent_deployment: context[:agent_deployment],
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("shell_exec", "workspace_variables_get"),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    context[:agent_deployment].update!(active_capability_snapshot: drifted_snapshot)

    AgentDeployments::RecordHeartbeat.call(
      deployment: context[:agent_deployment],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    resumed = AgentDeployments::AutoResumeWorkflows.call(deployment: context[:agent_deployment])

    assert_equal [], resumed

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "manual_recovery_required", workflow_run.wait_reason_kind
    assert_equal "paused_agent_unavailable", workflow_run.wait_reason_payload["recovery_state"]
    assert_equal "capability_snapshot_version_drift", workflow_run.wait_reason_payload["drift_reason"]
  end

  test "ignores waiting workflows whose conversations are pending delete" do
    context = build_waiting_recovery_context!
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)

    AgentDeployments::RecordHeartbeat.call(
      deployment: context[:agent_deployment],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    assert_equal [], AgentDeployments::AutoResumeWorkflows.call(deployment: context[:agent_deployment])
    assert context[:workflow_run].reload.waiting?
  end

  test "compatible rotated deployment auto resumes waiting workflows and rewrites turn pinning" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation],
      execution_environment: context[:execution_environment]
    )

    AgentDeployments::RecordHeartbeat.call(
      deployment: replacement,
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.2.0" },
      auto_resume_eligible: true
    )

    resumed = AgentDeployments::AutoResumeWorkflows.call(deployment: replacement)

    assert_equal [context[:workflow_run].id], resumed.map(&:id)
    assert_equal replacement, context[:conversation].reload.agent_deployment
    assert_equal replacement, context[:turn].reload.agent_deployment
    assert_equal replacement.fingerprint, context[:turn].pinned_deployment_fingerprint
    assert context[:workflow_run].reload.ready?
  end

  test "cross environment rotated deployments require manual recovery instead of auto resume" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation]
    )

    AgentDeployments::RecordHeartbeat.call(
      deployment: replacement,
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.2.0" },
      auto_resume_eligible: true
    )

    resumed = AgentDeployments::AutoResumeWorkflows.call(deployment: replacement)

    assert_equal [], resumed
    assert_equal context[:agent_deployment], context[:conversation].reload.agent_deployment
    assert_equal context[:agent_deployment], context[:turn].reload.agent_deployment
    assert_equal "manual_recovery_required", context[:workflow_run].reload.wait_reason_kind
    assert_equal "execution_environment_drift", context[:workflow_run].wait_reason_payload["drift_reason"]
  end

  test "restores the original human-interaction blocker after auto resume" do
    context = build_waiting_human_interaction_recovery_context!

    AgentDeployments::RecordHeartbeat.call(
      deployment: context[:agent_deployment],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    resumed = AgentDeployments::AutoResumeWorkflows.call(deployment: context[:agent_deployment])

    assert_equal [context[:workflow_run].id], resumed.map(&:id)

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "human_interaction", workflow_run.wait_reason_kind
    assert_equal "HumanInteractionRequest", workflow_run.blocking_resource_type
    assert_equal context[:request].public_id, workflow_run.blocking_resource_id
    assert_equal context[:request].public_id, workflow_run.wait_reason_payload["request_id"]
    assert_equal "HumanTaskRequest", workflow_run.wait_reason_payload["request_type"]
  end

  test "does not restore a human-interaction blocker that was resolved during the outage" do
    context = build_waiting_human_interaction_recovery_context!

    HumanInteractions::CompleteTask.call(
      human_task_request: context[:request],
      completion_payload: { "approved" => true }
    )

    AgentDeployments::RecordHeartbeat.call(
      deployment: context[:agent_deployment],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    resumed = AgentDeployments::AutoResumeWorkflows.call(deployment: context[:agent_deployment])

    assert_equal [context[:workflow_run].id], resumed.map(&:id)

    workflow_run = context[:workflow_run].reload
    assert workflow_run.ready?
    assert_nil workflow_run.wait_reason_kind
    assert_equal({}, workflow_run.wait_reason_payload)
    assert_nil workflow_run.blocking_resource_type
    assert_nil workflow_run.blocking_resource_id
  end

  private

  def build_waiting_recovery_context!
    context = prepare_workflow_execution_context!(create_workspace_context!)
    context[:agent_deployment].update!(auto_resume_eligible: true)
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

    AgentDeployments::MarkUnavailable.call(
      deployment: context[:agent_deployment],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    context.merge(conversation: conversation, turn: turn.reload, workflow_run: workflow_run.reload)
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
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("shell_exec", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    deployment.update!(active_capability_snapshot: capability_snapshot)
    deployment
  end
end
