require "test_helper"
require "action_cable/test_helper"

class MailboxDeliveryE2ETest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

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
    assert_equal "active", context[:deployment].reload.control_activity_state
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
      message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: scenario.fetch(:mailbox_item).public_id,
      agent_task_run_id: scenario.fetch(:agent_task_run).public_id,
      logical_work_id: scenario.fetch(:agent_task_run).logical_work_id,
      attempt_no: scenario.fetch(:agent_task_run).attempt_no,
      expected_duration_seconds: 30
    )

    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    close_request = scenario_builder.close_request!(context: context, resource: process_run).fetch(:mailbox_item)

    report_response = harness.report!(
      method_id: "execution_progress",
      message_id: "agent-progress-#{next_test_sequence}",
      mailbox_item_id: scenario.fetch(:mailbox_item).public_id,
      agent_task_run_id: scenario.fetch(:agent_task_run).public_id,
      logical_work_id: scenario.fetch(:agent_task_run).logical_work_id,
      attempt_no: scenario.fetch(:agent_task_run).attempt_no,
      progress_payload: { "percent" => 50 }
    )

    assert_equal 200, report_response.fetch("http_status")
    assert_equal [close_request.public_id], report_response.fetch("mailbox_items").map { |item| item.fetch("item_id") }
  end
end
