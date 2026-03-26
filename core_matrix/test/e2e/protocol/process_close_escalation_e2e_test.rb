require "test_helper"

class ProcessCloseEscalationE2ETest < ActionDispatch::IntegrationTest
  test "turn command process supports graceful close" do
    process_run = interrupt_process_run!(close_outcome_kind: "graceful")

    assert process_run.reload.stopped?
    assert_equal "graceful", process_run.close_outcome_kind
  end

  test "turn command process supports forced close after graceful escalation" do
    process_run = interrupt_process_run!(close_outcome_kind: "forced")

    assert process_run.reload.stopped?
    assert_equal "forced", process_run.close_outcome_kind
  end

  test "turn command process records residual abandonment when forced close still fails" do
    process_run = interrupt_process_run!(close_outcome_kind: "residual_abandoned")

    assert process_run.reload.lost?
    assert_equal "residual_abandoned", process_run.close_outcome_kind
  end

  private

  def interrupt_process_run!(close_outcome_kind:)
    context = build_agent_control_context!
    harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: context[:deployment],
      machine_credential: context[:machine_credential]
    )
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "turn_command"
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.zone.parse("2026-03-26 15:00:00 UTC"))

    close_request = harness.poll!.fetch("mailbox_items").find do |mailbox_item|
      mailbox_item.fetch("payload").fetch("resource_id") == process_run.public_id
    end

    harness.report!(
      method_id: "resource_closed",
      message_id: "close-#{next_test_sequence}",
      mailbox_item_id: close_request.fetch("item_id"),
      close_request_id: close_request.fetch("item_id"),
      resource_type: "ProcessRun",
      resource_id: process_run.public_id,
      close_outcome_kind: close_outcome_kind,
      close_outcome_payload: { "source" => "e2e" }
    )

    process_run
  end
end
