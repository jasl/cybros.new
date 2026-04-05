require "test_helper"

class WorkflowWaitSnapshotTest < ActiveSupport::TestCase
  test "captures and restores a human interaction wait state" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )
    workflow_run = context[:workflow_run].reload

    snapshot = WorkflowWaitSnapshot.capture(workflow_run)

    assert_equal "human_interaction", snapshot.wait_reason_kind
    assert_equal request.public_id, snapshot.blocking_resource_id
    assert_equal(
      {
        "wait_state" => "waiting",
        "wait_reason_kind" => "human_interaction",
        "wait_reason_payload" => {},
        "blocking_resource_type" => "HumanInteractionRequest",
        "blocking_resource_id" => request.public_id,
      },
      snapshot.restore_attributes.except("waiting_since_at")
    )
  end

  test "recognizes when a paused human interaction blocker has been resolved" do
    context = build_waiting_human_interaction_recovery_context!
    snapshot = WorkflowWaitSnapshot.from_workflow_run(context[:workflow_run])

    refute snapshot.resolved_for?(context[:workflow_run])

    HumanInteractions::CompleteTask.call(
      human_task_request: context[:request],
      completion_payload: { "approved" => true }
    )

    assert snapshot.resolved_for?(context[:workflow_run].reload)
  end

  test "loads a paused wait snapshot from the workflow wait snapshot document" do
    context = build_waiting_human_interaction_recovery_context!

    snapshot = WorkflowWaitSnapshot.from_workflow_run(context[:workflow_run])

    assert_equal context[:request].public_id, snapshot.blocking_resource_id
    assert_equal({}, snapshot.wait_reason_payload)
  end

  test "recognizes when a blocked workflow node is still unresolved" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    workflow_node.update!(lifecycle_state: "waiting", started_at: 1.minute.ago, finished_at: nil)
    workflow_run.turn.update!(lifecycle_state: "waiting")
    workflow_run.update!(
      wait_state: "waiting",
      wait_reason_kind: "external_dependency_blocked",
      wait_reason_payload: {},
      wait_failure_kind: "provider_rate_limited",
      wait_retry_scope: "step",
      wait_retry_strategy: "automatic",
      wait_attempt_no: 1,
      waiting_since_at: Time.current,
      blocking_resource_type: "WorkflowNode",
      blocking_resource_id: workflow_node.public_id
    )

    snapshot = WorkflowWaitSnapshot.capture(workflow_run)

    refute snapshot.resolved_for?(workflow_run)

    workflow_node.update!(lifecycle_state: "queued", started_at: nil, finished_at: nil)

    assert snapshot.resolved_for?(workflow_run.reload)
  end
end
