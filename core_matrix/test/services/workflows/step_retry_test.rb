require "test_helper"

class Workflows::StepRetryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "creates a new in-place attempt inside the same turn and workflow" do
    context = build_agent_control_context!
    failed_task = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "failed",
      logical_work_id: "retry-step",
      attempt_no: 1,
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      task_payload: { "step" => "execute", "tool_name" => "exec_command" },
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
    assert_equal(
      {
        "step" => "execute",
        "tool_name" => "exec_command",
        "delivery_kind" => "step_retry",
        "previous_attempt_no" => 1,
      },
      mailbox_item.payload["task_payload"]
    )

    workflow_run = context[:workflow_run].reload
    assert workflow_run.ready?
    assert_nil workflow_run.wait_reason_kind
    assert_nil workflow_run.blocking_resource_type
  end

  test "reuses the frozen execution snapshot envelope for retry assignments" do
    context = build_agent_control_context!
    failed_task = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "failed",
      logical_work_id: "retry-step",
      attempt_no: 1,
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      task_payload: { "step" => "execute", "tool_name" => "exec_command" },
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
    mailbox_item = AgentControlMailboxItem.find_by!(agent_task_run: retried_task)
    execution_snapshot = context[:turn].reload.execution_snapshot

    assert_equal execution_snapshot.conversation_projection, mailbox_item.payload["conversation_projection"]
    assert_equal execution_snapshot.capability_projection, mailbox_item.payload["capability_projection"]
    assert_equal execution_snapshot.provider_context, mailbox_item.payload["provider_context"]
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

  test "rejects retry for pending delete conversations on the workflow record" do
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
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::StepRetry.call(workflow_run: context[:workflow_run])
    end

    assert_equal context[:workflow_run].id, error.record.id
    assert_includes error.record.errors[:deletion_state], "must be retained before step retry"
  end

  test "rechecks the retry gate after loading the failed task" do
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

    service = Workflows::StepRetry.new(workflow_run: context[:workflow_run])
    inject_ready_state_after_failed_task_lookup!(service, context[:workflow_run])

    error = assert_raises(ActiveRecord::RecordInvalid) do
      service.call
    end

    assert_includes error.record.errors[:wait_reason_kind], "must be retryable_failure before step retry"
    assert_equal 0,
      AgentTaskRun.where(
        workflow_run: context[:workflow_run],
        logical_work_id: failed_task.logical_work_id,
        attempt_no: 2
      ).count
  end

  test "resumes a retryable blocked workflow node in place" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    workflow_node.update!(lifecycle_state: "waiting", started_at: 1.minute.ago, finished_at: nil)
    workflow_run.turn.update!(lifecycle_state: "waiting")
    workflow_run.update!(
      wait_state: "waiting",
      wait_reason_kind: "retryable_failure",
      wait_reason_payload: {
        "failure_kind" => "provider_round_limit_exceeded",
        "retry_scope" => "step",
      },
      waiting_since_at: Time.current,
      blocking_resource_type: "WorkflowNode",
      blocking_resource_id: workflow_node.public_id
    )

    assert_enqueued_with(job: Workflows::ExecuteNodeJob, args: [workflow_node.public_id]) do
      resumed_node = Workflows::StepRetry.call(workflow_run: workflow_run)
      assert_equal workflow_node.public_id, resumed_node.public_id
    end

    assert_equal "queued", workflow_node.reload.lifecycle_state
    assert_equal "ready", workflow_run.reload.wait_state
  end

  private

  def inject_ready_state_after_failed_task_lookup!(service, workflow_run)
    injected = false

    service.singleton_class.prepend(Module.new do
      define_method(:blocking_agent_task) do |*args|
        super(*args).tap do
          next if injected

          injected = true
          workflow_run.update!(
            wait_state: "ready",
            wait_reason_kind: nil,
            wait_reason_payload: {},
            waiting_since_at: nil,
            blocking_resource_type: nil,
            blocking_resource_id: nil
          )
        end
      end
    end)
  end
end
