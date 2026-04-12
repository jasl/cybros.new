require "test_helper"

class AgentDefinitionVersions::MarkUnavailableTest < ActiveSupport::TestCase
  test "marks active work as waiting during a transient outage and records degradation" do
    context = build_recovery_context!

    AgentDefinitionVersions::MarkUnavailable.call(
      agent_definition_version: context[:agent_definition_version],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "agent_unavailable", workflow_run.wait_reason_kind
    assert_equal "transient_outage", workflow_run.recovery_state
    assert_equal "heartbeat_missed", workflow_run.recovery_reason
    assert_equal context[:agent_definition_version].public_id, workflow_run.blocking_resource_id
    assert_equal "AgentDefinitionVersion", workflow_run.blocking_resource_type
    assert_equal({}, workflow_run.wait_reason_payload)

    agent_definition_version = context[:agent_definition_version].reload
    assert agent_definition_version.degraded?

    audit_log = AuditLog.find_by!(action: "agent_definition_version.degraded")
    assert_equal agent_definition_version, audit_log.subject
    assert_equal [workflow_run.id], audit_log.metadata["workflow_run_ids"]
  end

  test "moves waiting work into paused agent unavailable on prolonged outage" do
    context = build_recovery_context!
    AgentDefinitionVersions::MarkUnavailable.call(
      agent_definition_version: context[:agent_definition_version],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    AgentDefinitionVersions::MarkUnavailable.call(
      agent_definition_version: context[:agent_definition_version],
      severity: "prolonged",
      reason: "runtime_offline",
      occurred_at: 5.minutes.from_now
    )

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "manual_recovery_required", workflow_run.wait_reason_kind
    assert_equal "paused_agent_unavailable", workflow_run.recovery_state
    assert_equal "runtime_offline", workflow_run.recovery_reason

    agent_definition_version = context[:agent_definition_version].reload
    assert agent_definition_version.offline?
    assert_not agent_definition_version.auto_resume_eligible?

    audit_log = AuditLog.find_by!(action: "agent_definition_version.paused_agent_unavailable")
    assert_equal agent_definition_version, audit_log.subject
    assert_equal [workflow_run.id], audit_log.metadata["workflow_run_ids"]
  end

  test "snapshots the original human-interaction blocker instead of discarding it" do
    context = build_human_interaction_context!
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

    workflow_run = context[:workflow_run].reload
    snapshot = workflow_run.wait_snapshot_document.payload

    assert workflow_run.waiting?
    assert_equal "agent_unavailable", workflow_run.wait_reason_kind
    assert_equal "human_interaction", snapshot["wait_reason_kind"]
    assert_equal request.public_id, snapshot["blocking_resource_id"]
    assert_equal "HumanInteractionRequest", snapshot["blocking_resource_type"]
    assert_equal({}, snapshot["wait_reason_payload"])
  end

  test "rechecks workflow activity before applying the unavailable wait state" do
    context = build_recovery_context!
    service = AgentDefinitionVersions::MarkUnavailable.new(
      agent_definition_version: context[:agent_definition_version],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )
    inject_completed_state_before_pause!(service, context[:workflow_run])

    result = service.call

    assert_equal [], result.workflow_runs.map(&:id)

    workflow_run = context[:workflow_run].reload
    assert workflow_run.completed?
    assert workflow_run.ready?
    assert_nil workflow_run.wait_reason_kind
    assert_equal({}, workflow_run.wait_reason_payload)
  end

  private

  def build_recovery_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Recovery input",
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

  def inject_completed_state_before_pause!(service, workflow_run)
    injected = false

    service.singleton_class.prepend(Module.new do
      define_method(:apply_wait_state!) do |current_workflow_run|
        unless injected
          injected = true
          workflow_run.update!(lifecycle_state: "completed")
        end

        super(current_workflow_run)
      end
    end)
  end
end
