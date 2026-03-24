require "test_helper"

class AgentDeployments::MarkUnavailableTest < ActiveSupport::TestCase
  test "marks active work as waiting during a transient outage and records degradation" do
    context = build_recovery_context!

    AgentDeployments::MarkUnavailable.call(
      deployment: context[:agent_deployment],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "agent_unavailable", workflow_run.wait_reason_kind
    assert_equal "transient_outage", workflow_run.wait_reason_payload["recovery_state"]
    assert_equal context[:agent_deployment].id.to_s, workflow_run.blocking_resource_id
    assert_equal "AgentDeployment", workflow_run.blocking_resource_type
    assert_equal context[:agent_deployment].fingerprint, workflow_run.wait_reason_payload["pinned_deployment_fingerprint"]
    assert_equal context[:capability_snapshot].version, workflow_run.wait_reason_payload["pinned_capability_version"]

    deployment = context[:agent_deployment].reload
    assert deployment.degraded?

    audit_log = AuditLog.find_by!(action: "agent_deployment.degraded")
    assert_equal deployment, audit_log.subject
    assert_equal [workflow_run.id], audit_log.metadata["workflow_run_ids"]
  end

  test "moves waiting work into paused agent unavailable on prolonged outage" do
    context = build_recovery_context!
    AgentDeployments::MarkUnavailable.call(
      deployment: context[:agent_deployment],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    AgentDeployments::MarkUnavailable.call(
      deployment: context[:agent_deployment],
      severity: "prolonged",
      reason: "runtime_offline",
      occurred_at: 5.minutes.from_now
    )

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "manual_recovery_required", workflow_run.wait_reason_kind
    assert_equal "paused_agent_unavailable", workflow_run.wait_reason_payload["recovery_state"]
    assert_equal "runtime_offline", workflow_run.wait_reason_payload["reason"]

    deployment = context[:agent_deployment].reload
    assert deployment.offline?
    assert_not deployment.auto_resume_eligible?

    audit_log = AuditLog.find_by!(action: "agent_deployment.paused_agent_unavailable")
    assert_equal deployment, audit_log.subject
    assert_equal [workflow_run.id], audit_log.metadata["workflow_run_ids"]
  end

  private

  def build_recovery_context!
    context = prepare_workflow_execution_context!(create_workspace_context!)
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

    context.merge(conversation: conversation, turn: turn.reload, workflow_run: workflow_run.reload)
  end
end
