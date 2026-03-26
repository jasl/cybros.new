require "test_helper"

class Conversations::RequestTurnInterruptTest < ActiveSupport::TestCase
  test "creates a close fence and requests close for mainline runtime resources only" do
    context = build_agent_control_context!
    blocking_request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )
    optional_request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: false,
      request_payload: { "instructions" => "Optional follow up" }
    )
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )
    Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    turn_command = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "turn_command"
    )
    background_service = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: turn_command,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    Leases::Acquire.call(
      leased_resource: background_service,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    subagent_run = create_subagent_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running"
    )
    Leases::Acquire.call(
      leased_resource: subagent_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.zone.parse("2026-03-26 12:00:00 UTC"))

    assert_equal "turn_interrupted", context[:turn].reload.cancellation_reason_kind
    assert_equal "turn_interrupted", context[:workflow_run].reload.cancellation_reason_kind
    assert context[:turn].active?
    assert context[:workflow_run].active?

    assert blocking_request.reload.canceled?
    assert_equal "turn_interrupted", blocking_request.result_payload["reason"]
    assert optional_request.reload.open?

    assert_equal "requested", agent_task_run.reload.close_state
    assert_equal "requested", turn_command.reload.close_state
    assert_equal "requested", subagent_run.reload.close_state
    assert_equal "open", background_service.reload.close_state

    close_requests = AgentControlMailboxItem.where(item_type: "resource_close_request").order(:created_at)
    assert_equal 3, close_requests.count
    assert_equal [agent_task_run.public_id, turn_command.public_id, subagent_run.public_id].sort,
      close_requests.pluck(Arel.sql("payload ->> 'resource_id'")).sort
    assert_equal ["turn_interrupt"], close_requests.reorder(nil).distinct.pluck(Arel.sql("payload ->> 'request_kind'"))
  end

  test "cancels queued step retry work when the turn is fenced" do
    context = build_agent_control_context!
    failed_task = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "failed",
      logical_work_id: "retry-me",
      attempt_no: 1,
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      task_payload: { "step" => "tool_call" },
      terminal_payload: {
        "retryable" => true,
        "retry_scope" => "step",
        "failure_kind" => "tool_failure",
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
    queued_retry = Workflows::StepRetry.call(workflow_run: context[:workflow_run])

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.zone.parse("2026-03-26 12:05:00 UTC"))

    assert queued_retry.reload.canceled?
    assert_not_nil queued_retry.finished_at
    assert_equal "turn_interrupted", queued_retry.terminal_payload["cancellation_reason_kind"]

    retry_mailbox_item = AgentControlMailboxItem.find_by!(agent_task_run: queued_retry)
    assert_equal "canceled", retry_mailbox_item.status
  end
end
