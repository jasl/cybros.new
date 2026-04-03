require "test_helper"
require "action_cable/test_helper"

class MailboxDeliveryE2ETest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  test "poll-only delivery drives assignment progress and completion without a websocket session" do
    context = build_agent_control_context!
    harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: context[:deployment],
      machine_credential: context[:machine_credential]
    )
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(
      context: context,
      task_payload: { "mode" => "poll-only" }
    )

    assert_empty harness.websocket_mailbox_items

    poll_response = harness.poll!
    assignment = poll_response.fetch("mailbox_items").fetch(0)

    assert_equal scenario.fetch(:mailbox_item).public_id, assignment.fetch("item_id")
    assert_equal "execution_assignment", assignment.fetch("item_type")
    assert_equal "program", assignment.fetch("runtime_plane")
    assert_equal context[:agent_program].public_id, assignment.fetch("target_ref")
    refute assignment.fetch("payload").key?("runtime_plane")

    started = report_execution_started(
      harness: harness,
      assignment: assignment,
      agent_task_run: scenario.fetch(:agent_task_run),
      protocol_message_id: "poll-start-#{next_test_sequence}"
    )
    progress = harness.report!(
      method_id: "execution_progress",
      protocol_message_id: "poll-progress-#{next_test_sequence}",
      mailbox_item_id: assignment.fetch("item_id"),
      agent_task_run_id: scenario.fetch(:agent_task_run).public_id,
      logical_work_id: scenario.fetch(:agent_task_run).logical_work_id,
      attempt_no: scenario.fetch(:agent_task_run).attempt_no,
      progress_payload: { "percent" => 50 }
    )
    completed = harness.report!(
      method_id: "execution_complete",
      protocol_message_id: "poll-complete-#{next_test_sequence}",
      mailbox_item_id: assignment.fetch("item_id"),
      agent_task_run_id: scenario.fetch(:agent_task_run).public_id,
      logical_work_id: scenario.fetch(:agent_task_run).logical_work_id,
      attempt_no: scenario.fetch(:agent_task_run).attempt_no,
      terminal_payload: { "output" => "poll completed" }
    )

    assert_equal 200, started.fetch("http_status")
    assert_equal "accepted", started.fetch("result")
    assert_equal 200, progress.fetch("http_status")
    assert_equal "accepted", progress.fetch("result")
    assert_equal 200, completed.fetch("http_status")
    assert_equal "accepted", completed.fetch("result")
    assert_equal "completed", scenario.fetch(:mailbox_item).reload.status
    assert_equal "completed", scenario.fetch(:agent_task_run).reload.lifecycle_state
    assert_equal "poll completed", scenario.fetch(:agent_task_run).terminal_payload.fetch("output")
    assert_equal "active_control", context[:deployment].reload.control_activity_state
  end

  test "websocket delivery and poll fallback expose the same mailbox envelope" do
    context = build_agent_control_context!
    harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: context[:deployment],
      machine_credential: context[:machine_credential]
    )
    scenario_builder = MailboxScenarioBuilder.new(self)

    harness.connect_websocket!
    websocket_payloads = harness.capture_websocket_mailbox_items do
      scenario_builder.execution_assignment!(context: context, task_payload: { "mode" => "websocket" })
    end

    poll_response = harness.poll!

    assert_equal 1, websocket_payloads.size
    assert_equal [websocket_payloads.fetch(0)], poll_response.fetch("mailbox_items")
  end

  test "duplicate execution_complete is idempotent during a poll-only lifecycle" do
    context = build_agent_control_context!
    harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: context[:deployment],
      machine_credential: context[:machine_credential]
    )
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    assignment = harness.poll!.fetch("mailbox_items").fetch(0)
    protocol_message_id = "poll-complete-duplicate-#{next_test_sequence}"

    report_execution_started(
      harness: harness,
      assignment: assignment,
      agent_task_run: scenario.fetch(:agent_task_run),
      protocol_message_id: "poll-start-duplicate-#{next_test_sequence}"
    )

    first_terminal = harness.report!(
      method_id: "execution_complete",
      protocol_message_id: protocol_message_id,
      mailbox_item_id: assignment.fetch("item_id"),
      agent_task_run_id: scenario.fetch(:agent_task_run).public_id,
      logical_work_id: scenario.fetch(:agent_task_run).logical_work_id,
      attempt_no: scenario.fetch(:agent_task_run).attempt_no,
      terminal_payload: { "output" => "done once" }
    )
    first_updated_at = scenario.fetch(:agent_task_run).reload.updated_at

    duplicate_terminal = harness.report!(
      method_id: "execution_complete",
      protocol_message_id: protocol_message_id,
      mailbox_item_id: assignment.fetch("item_id"),
      agent_task_run_id: scenario.fetch(:agent_task_run).public_id,
      logical_work_id: scenario.fetch(:agent_task_run).logical_work_id,
      attempt_no: scenario.fetch(:agent_task_run).attempt_no,
      terminal_payload: { "output" => "done once" }
    )

    assert_equal 200, first_terminal.fetch("http_status")
    assert_equal "accepted", first_terminal.fetch("result")
    assert_equal 200, duplicate_terminal.fetch("http_status")
    assert_equal "duplicate", duplicate_terminal.fetch("result")
    assert_equal first_updated_at, scenario.fetch(:agent_task_run).reload.updated_at
    assert_equal "done once", scenario.fetch(:agent_task_run).terminal_payload.fetch("output")
  end

  test "websocket disconnect falls back to poll while control activity remains active" do
    context = build_agent_control_context!
    harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: context[:deployment],
      machine_credential: context[:machine_credential]
    )

    harness.connect_websocket!
    harness.disconnect_websocket!

    MailboxScenarioBuilder.new(self).execution_assignment!(context: context, task_payload: { "mode" => "poll" })
    poll_response = harness.poll!

    assert_equal 1, poll_response.fetch("mailbox_items").size
    assert_equal "disconnected", context[:deployment].reload.realtime_link_state
    assert_equal "active_control", context[:deployment].reload.control_activity_state
  end

  test "report responses piggyback pending close control work onto the active runtime session" do
    context = build_agent_control_context!
    harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: context[:deployment],
      machine_credential: context[:machine_credential]
    )
    scenario_builder = MailboxScenarioBuilder.new(self)
    scenario = scenario_builder.execution_assignment!(context: context)
    harness.poll!
    harness.report!(
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: scenario.fetch(:mailbox_item).public_id,
      agent_task_run_id: scenario.fetch(:agent_task_run).public_id,
      logical_work_id: scenario.fetch(:agent_task_run).logical_work_id,
      attempt_no: scenario.fetch(:agent_task_run).attempt_no,
      expected_duration_seconds: 30
    )

    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    close_request = scenario_builder.close_request!(context: context, resource: process_run).fetch(:mailbox_item)

    report_response = harness.report!(
      method_id: "execution_progress",
      protocol_message_id: "agent-progress-#{next_test_sequence}",
      mailbox_item_id: scenario.fetch(:mailbox_item).public_id,
      agent_task_run_id: scenario.fetch(:agent_task_run).public_id,
      logical_work_id: scenario.fetch(:agent_task_run).logical_work_id,
      attempt_no: scenario.fetch(:agent_task_run).attempt_no,
      progress_payload: { "percent" => 50 }
    )

    assert_equal 200, report_response.fetch("http_status")
    assert_equal [close_request.public_id], report_response.fetch("mailbox_items").map { |item| item.fetch("item_id") }
  end

  private

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
end
