require "test_helper"

class TurnInterruptE2ETest < ActionDispatch::IntegrationTest
  test "execution terminal reports only mutate the lifecycle path for the accepted holder deployment" do
    context = build_agent_control_context!
    holder_harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: context[:deployment],
      machine_credential: context[:machine_credential]
    )
    sibling_agent_installation = create_agent_installation!(installation: context[:installation])
    sibling_execution_environment = create_execution_environment!(installation: context[:installation])
    sibling_registration = register_agent_runtime!(
      installation: context[:installation],
      actor: context[:actor],
      agent_installation: sibling_agent_installation,
      execution_environment: sibling_execution_environment,
      reuse_enrollment: true
    )
    sibling_registration.fetch(:deployment).update!(
      bootstrap_state: "active",
      health_status: "healthy",
      last_heartbeat_at: Time.current
    )
    sibling_harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: sibling_registration.fetch(:deployment),
      machine_credential: sibling_registration.fetch(:machine_credential)
    )
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    assignment = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    holder_harness.poll!
    holder_harness.report!(
      method_id: "execution_started",
      message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: assignment.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 30
    )

    sibling_terminal = sibling_harness.report!(
      method_id: "execution_complete",
      message_id: "sibling-terminal-#{next_test_sequence}",
      mailbox_item_id: assignment.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: { "output" => "wrong deployment" }
    )

    assert_equal 409, sibling_terminal.fetch("http_status")
    assert_equal "stale", sibling_terminal.fetch("result")
    assert_equal "running", agent_task_run.reload.lifecycle_state
    assert_equal context[:deployment], agent_task_run.holder_agent_deployment

    holder_terminal = holder_harness.report!(
      method_id: "execution_complete",
      message_id: "holder-terminal-#{next_test_sequence}",
      mailbox_item_id: assignment.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: { "output" => "accepted deployment" }
    )

    assert_equal 200, holder_terminal.fetch("http_status")
    assert_equal "accepted", holder_terminal.fetch("result")
    assert_equal "completed", agent_task_run.reload.lifecycle_state
  end

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
