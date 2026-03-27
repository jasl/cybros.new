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
        "wait_reason_payload" => {
          "request_id" => request.public_id,
          "request_type" => "HumanTaskRequest",
        },
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
end
