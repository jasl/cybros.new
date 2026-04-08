require "test_helper"

class AgentControl::ApplyCloseOutcomeTest < ActiveSupport::TestCase
  test "terminalizes a closed process run, releases its lease, and completes the mailbox item" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-03-29 18:30:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run,
      request_kind: "turn_interrupt",
      reason_kind: "turn_interrupted"
    ).fetch(:mailbox_item)

    result = AgentControl::ApplyCloseOutcome.call(
      resource: process_run,
      mailbox_item: mailbox_item,
      close_state: "closed",
      close_outcome_kind: "graceful",
      close_outcome_payload: { "source" => "agent" },
      occurred_at: occurred_at
    )

    assert_equal process_run, result
    assert result.close_closed?
    assert result.stopped?
    assert_equal "turn_interrupted", result.metadata["stop_reason"]
    assert_equal "turn_interrupt", result.metadata["close_request_kind"]
    assert_equal "completed", mailbox_item.reload.status
    assert_not result.execution_lease.active?
  end
end
