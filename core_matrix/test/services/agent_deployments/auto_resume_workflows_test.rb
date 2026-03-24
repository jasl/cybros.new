require "test_helper"

class AgentDeployments::AutoResumeWorkflowsTest < ActiveSupport::TestCase
  test "automatically resumes waiting workflows when runtime identity did not drift" do
    context = build_waiting_recovery_context!

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

  private

  def build_waiting_recovery_context!
    context = prepare_workflow_execution_context!(create_workspace_context!)
    context[:agent_deployment].update!(auto_resume_eligible: true)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
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
end
