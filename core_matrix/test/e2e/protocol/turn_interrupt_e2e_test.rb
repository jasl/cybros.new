require "test_helper"

class TurnInterruptE2ETest < ActionDispatch::IntegrationTest
  test "turn interrupt fences late execution reports and cancels the turn once mainline close completes" do
    context = build_agent_control_context!
    harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: context[:deployment],
      machine_credential: context[:machine_credential]
    )
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    assignment = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "turn_command"
    )
    subagent_run = create_subagent_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running"
    )
    [agent_task_run, process_run, subagent_run].each do |resource|
      Leases::Acquire.call(
        leased_resource: resource,
        holder_key: context[:deployment].public_id,
        heartbeat_timeout_seconds: 30
      )
    end

    harness.poll!
    harness.report!(
      method_id: "execution_started",
      message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: assignment.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 30
    )

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.zone.parse("2026-03-26 13:00:00 UTC"))

    late_progress = harness.report!(
      method_id: "execution_progress",
      message_id: "late-progress-#{next_test_sequence}",
      mailbox_item_id: assignment.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      progress_payload: { "state" => "late" }
    )

    assert_equal 409, late_progress.fetch("http_status")
    assert_equal "stale", late_progress.fetch("result")

    close_requests = harness.poll!.fetch("mailbox_items")
    assert_equal 3, close_requests.size

    close_requests.each do |mailbox_item|
      report_resource_closed!(
        harness: harness,
        mailbox_item: mailbox_item,
        close_outcome_kind: "graceful"
      )
    end

    late_terminal = harness.report!(
      method_id: "execution_complete",
      message_id: "late-terminal-#{next_test_sequence}",
      mailbox_item_id: assignment.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: { "output" => "too late" }
    )

    assert_equal 409, late_terminal.fetch("http_status")
    assert_equal "stale", late_terminal.fetch("result")
    assert context[:turn].reload.canceled?
    assert context[:workflow_run].reload.canceled?
    assert process_run.reload.stopped?
    assert subagent_run.reload.canceled?
  end

  private

  def report_resource_closed!(harness:, mailbox_item:, close_outcome_kind:)
    harness.report!(
      method_id: "resource_closed",
      message_id: "close-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.fetch("item_id"),
      close_request_id: mailbox_item.fetch("item_id"),
      resource_type: mailbox_item.fetch("payload").fetch("resource_type"),
      resource_id: mailbox_item.fetch("payload").fetch("resource_id"),
      close_outcome_kind: close_outcome_kind,
      close_outcome_payload: { "source" => "e2e" }
    )
  end
end
