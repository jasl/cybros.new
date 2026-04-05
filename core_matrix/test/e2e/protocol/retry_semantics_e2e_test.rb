require "test_helper"

class RetrySemanticsE2ETest < ActionDispatch::IntegrationTest
  test "retryable execution failure enters retryable_failure and step retry creates a new attempt in the same turn and workflow" do
    context = build_agent_control_context!
    harness = build_harness(context:)
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    initial_assignment = harness.poll!.fetch("mailbox_items").fetch(0)
    initial_task = scenario.fetch(:agent_task_run)

    report_execution_started(
      harness: harness,
      assignment: initial_assignment,
      agent_task_run: initial_task,
      protocol_message_id: "retry-start-#{next_test_sequence}"
    )
    failed = harness.report!(
      method_id: "execution_fail",
      protocol_message_id: "retry-fail-#{next_test_sequence}",
      mailbox_item_id: initial_assignment.fetch("item_id"),
      agent_task_run_id: initial_task.public_id,
      logical_work_id: initial_task.logical_work_id,
      attempt_no: initial_task.attempt_no,
      terminal_payload: {
        "retryable" => true,
        "retry_scope" => "step",
        "failure_kind" => "tool_failure",
        "last_error_summary" => "exit status 1",
      }
    )

    workflow_run = context[:workflow_run].reload

    assert_equal 200, failed.fetch("http_status")
    assert_equal "accepted", failed.fetch("result")
    assert workflow_run.waiting?
    assert_equal "retryable_failure", workflow_run.wait_reason_kind
    assert_equal "step", workflow_run.wait_retry_scope
    assert_equal "tool_failure", workflow_run.wait_failure_kind
    assert_equal initial_task.attempt_no, workflow_run.wait_attempt_no
    assert_equal "exit status 1", workflow_run.wait_last_error_summary
    assert_equal({}, workflow_run.wait_reason_payload)
    assert_equal initial_task.public_id, workflow_run.blocking_resource_id

    retried_task = Workflows::StepRetry.call(workflow_run: workflow_run)
    retry_assignment = AgentControlMailboxItem.find_by!(agent_task_run: retried_task)
    retry_delivery = harness.poll!.fetch("mailbox_items").fetch(0)

    assert_equal workflow_run, retried_task.workflow_run
    assert_equal context[:turn], retried_task.turn
    assert_equal context[:workflow_node], retried_task.workflow_node
    assert_equal initial_task.logical_work_id, retried_task.logical_work_id
    assert_equal 2, retried_task.attempt_no
    assert_equal retry_assignment.public_id, retry_delivery.fetch("item_id")
    assert_equal retried_task, AgentTaskRun.where(workflow_run: workflow_run.reload, attempt_no: 2).sole
  end

  test "turn interrupt fences a queued step retry before it can be delivered" do
    context = build_agent_control_context!
    harness = build_harness(context:)
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    initial_assignment = harness.poll!.fetch("mailbox_items").fetch(0)
    initial_task = scenario.fetch(:agent_task_run)

    report_execution_started(
      harness: harness,
      assignment: initial_assignment,
      agent_task_run: initial_task,
      protocol_message_id: "retry-fence-start-#{next_test_sequence}"
    )
    report_retryable_failure!(
      harness: harness,
      assignment: initial_assignment,
      agent_task_run: initial_task,
      protocol_message_id: "retry-fence-fail-#{next_test_sequence}"
    )

    retried_task = Workflows::StepRetry.call(workflow_run: context[:workflow_run].reload)
    retry_assignment = AgentControlMailboxItem.find_by!(agent_task_run: retried_task)

    Conversations::RequestTurnInterrupt.call(
      turn: context[:turn],
      occurred_at: Time.zone.parse("2026-03-29 10:00:00 UTC")
    )

    assert retried_task.reload.canceled?
    assert_equal "canceled", retry_assignment.reload.status
    assert_empty harness.poll!.fetch("mailbox_items").select { |item| item.fetch("item_type") == "execution_assignment" }
  end

  test "turn interrupt cancels queued retry work without surfacing detached background services as mainline close work" do
    context = build_agent_control_context!
    harness = build_harness(context:)
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    initial_assignment = harness.poll!.fetch("mailbox_items").fetch(0)
    initial_task = scenario.fetch(:agent_task_run)
    background_service = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: background_service,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )

    report_execution_started(
      harness: harness,
      assignment: initial_assignment,
      agent_task_run: initial_task,
      protocol_message_id: "retry-priority-start-#{next_test_sequence}"
    )
    report_retryable_failure!(
      harness: harness,
      assignment: initial_assignment,
      agent_task_run: initial_task,
      protocol_message_id: "retry-priority-fail-#{next_test_sequence}"
    )

    retried_task = Workflows::StepRetry.call(workflow_run: context[:workflow_run].reload)
    retry_assignment = AgentControlMailboxItem.find_by!(agent_task_run: retried_task)

    Conversations::RequestTurnInterrupt.call(
      turn: context[:turn],
      occurred_at: Time.zone.parse("2026-03-29 10:05:00 UTC")
    )

    assert retried_task.reload.canceled?
    assert_equal "canceled", retry_assignment.reload.status
    assert_equal "open", background_service.reload.close_state
    assert_empty harness.poll!(limit: 1).fetch("mailbox_items")
  end

  private

  def build_harness(context:)
    FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: context[:deployment],
      machine_credential: context[:machine_credential]
    )
  end

  def report_execution_started(harness:, assignment:, agent_task_run:, protocol_message_id:)
    harness.report!(
      method_id: "execution_started",
      protocol_message_id: protocol_message_id,
      mailbox_item_id: assignment.fetch("item_id"),
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 30
    )
  end

  def report_retryable_failure!(harness:, assignment:, agent_task_run:, protocol_message_id:)
    harness.report!(
      method_id: "execution_fail",
      protocol_message_id: protocol_message_id,
      mailbox_item_id: assignment.fetch("item_id"),
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: {
        "retryable" => true,
        "retry_scope" => "step",
        "failure_kind" => "tool_failure",
        "last_error_summary" => "exit status 1",
      }
    )
  end
end
