require "test_helper"

class Workflows::StepRetryTest < ActiveSupport::TestCase
  test "creates a new in-place attempt inside the same turn and workflow" do
    context = build_agent_control_context!
    failed_task = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "failed",
      logical_work_id: "retry-step",
      attempt_no: 1,
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      task_payload: { "step" => "execute", "tool_name" => "shell_exec" },
      terminal_payload: {
        "retryable" => true,
        "retry_scope" => "step",
        "failure_kind" => "tool_failure",
        "last_error_summary" => "exit status 1",
      }
    )
    context[:workflow_run].update!(
      wait_state: "waiting",
      wait_reason_kind: "retryable_failure",
      wait_reason_payload: {
        "retryable" => true,
        "retry_scope" => "step",
        "logical_work_id" => failed_task.logical_work_id,
        "attempt_no" => failed_task.attempt_no,
        "last_error_summary" => "exit status 1",
      },
      waiting_since_at: Time.current,
      blocking_resource_type: "AgentTaskRun",
      blocking_resource_id: failed_task.public_id
    )

    retried_task = Workflows::StepRetry.call(workflow_run: context[:workflow_run])

    assert_equal context[:workflow_run], retried_task.workflow_run
    assert_equal context[:turn], retried_task.turn
    assert_equal context[:workflow_node], retried_task.workflow_node
    assert_equal failed_task.logical_work_id, retried_task.logical_work_id
    assert_equal 2, retried_task.attempt_no
    assert_equal failed_task.task_payload, retried_task.task_payload
    assert retried_task.queued?

    mailbox_item = AgentControlMailboxItem.find_by!(agent_task_run: retried_task)
    assert_equal "execution_assignment", mailbox_item.item_type
    assert_equal 2, mailbox_item.priority
    assert_equal "step_retry", mailbox_item.payload["delivery_kind"]
    assert_equal 1, mailbox_item.payload["previous_attempt_no"]

    workflow_run = context[:workflow_run].reload
    assert workflow_run.ready?
    assert_nil workflow_run.wait_reason_kind
    assert_nil workflow_run.blocking_resource_type
  end

  test "rejects retry when the turn has already been interrupted" do
    context = build_agent_control_context!
    failed_task = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "failed",
      logical_work_id: "retry-step",
      attempt_no: 1,
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      terminal_payload: {
        "retryable" => true,
        "retry_scope" => "step",
      }
    )
    context[:workflow_run].update!(
      wait_state: "waiting",
      wait_reason_kind: "retryable_failure",
      wait_reason_payload: {
        "retryable" => true,
        "retry_scope" => "step",
        "logical_work_id" => failed_task.logical_work_id,
        "attempt_no" => failed_task.attempt_no,
      },
      waiting_since_at: Time.current,
      blocking_resource_type: "AgentTaskRun",
      blocking_resource_id: failed_task.public_id
    )
    context[:turn].update!(
      cancellation_requested_at: Time.current,
      cancellation_reason_kind: "turn_interrupted"
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::StepRetry.call(workflow_run: context[:workflow_run])
    end

    assert_includes error.record.errors[:turn], "must not be fenced by turn interrupt"
  end
end
