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

  test "cancels leased execution assignments so they are not redelivered after interrupt" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    deliveries = AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    assert_equal [mailbox_item.id], deliveries.map(&:id)
    assert_equal "leased", mailbox_item.reload.status

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.zone.parse("2026-03-27 12:10:00 UTC"))

    assert agent_task_run.reload.canceled?
    assert_equal "canceled", mailbox_item.reload.status
    assert_nil mailbox_item.leased_to_agent_deployment
    assert_empty AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
  end

  test "requests subagent close even when the running subagent has no lease" do
    context = build_agent_control_context!
    subagent_run = create_subagent_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running"
    )

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.zone.parse("2026-03-27 10:00:00 UTC"))

    close_request = AgentControlMailboxItem.find_by!(
      item_type: "resource_close_request",
      target_agent_installation: context[:agent_installation]
    )

    assert_equal "requested", subagent_run.reload.close_state
    assert_equal subagent_run.public_id, close_request.payload.fetch("resource_id")
    assert_equal "SubagentRun", close_request.payload.fetch("resource_type")
    assert_equal "agent", close_request.runtime_plane
    assert_equal "agent_installation", close_request.target_kind
    assert_equal context[:agent_installation].public_id, close_request.target_ref
  end

  test "reconciles an unfinished archive close after local mainline blockers are canceled" do
    context = build_agent_control_context!
    close_operation = ConversationCloseOperation.create!(
      installation: context[:conversation].installation,
      conversation: context[:conversation],
      intent_kind: "archive",
      lifecycle_state: "quiescing",
      requested_at: Time.zone.parse("2026-03-27 10:15:00 UTC"),
      summary_payload: {}
    )

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.zone.parse("2026-03-27 10:16:00 UTC"))

    assert context[:conversation].reload.archived?
    assert_equal "completed", close_operation.reload.lifecycle_state
    assert_not_nil close_operation.completed_at
    assert_equal 0, close_operation.summary_payload.dig("mainline", "active_turn_count")
    assert_equal 0, close_operation.summary_payload.dig("mainline", "active_workflow_count")
  end
end
