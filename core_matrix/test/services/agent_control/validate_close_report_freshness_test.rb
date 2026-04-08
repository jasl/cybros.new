require "test_helper"

class AgentControl::ValidateCloseReportFreshnessTest < ActiveSupport::TestCase
  test "accepts fresh close reports for the leased executor session" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-03-29 20:30:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program]
    )
    mailbox_item = travel_to(occurred_at) do
      AgentControl::CreateResourceCloseRequest.call(
        resource: process_run,
        request_kind: "turn_interrupt",
        reason_kind: "operator_stop",
        strictness: "graceful",
        grace_deadline_at: occurred_at + 30.seconds,
        force_deadline_at: occurred_at + 60.seconds
      )
    end

    AgentControl::Poll.call(executor_session: context[:executor_session], limit: 10, occurred_at: occurred_at)

    result = AgentControl::ValidateCloseReportFreshness.call(
      deployment: context[:deployment],
      executor_session: context[:executor_session],
      payload: { "close_request_id" => mailbox_item.public_id },
      mailbox_item: mailbox_item.reload,
      resource: process_run.reload,
      occurred_at: occurred_at
    )

    assert_nil result
  end

  test "rejects close reports from the wrong executor session after leasing moved elsewhere" do
    context = build_rotated_runtime_context!
    occurred_at = Time.zone.parse("2026-03-29 20:45:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program]
    )
    mailbox_item = travel_to(occurred_at) do
      AgentControl::CreateResourceCloseRequest.call(
        resource: process_run,
        request_kind: "turn_interrupt",
        reason_kind: "operator_stop",
        strictness: "graceful",
        grace_deadline_at: occurred_at + 30.seconds,
        force_deadline_at: occurred_at + 60.seconds
      )
    end

    previous_executor_session = context.fetch(:registration).fetch(:executor_session)

    AgentControl::Poll.call(executor_session: context[:executor_session], limit: 10, occurred_at: occurred_at)

    assert_raises(AgentControl::Report::StaleReportError) do
      AgentControl::ValidateCloseReportFreshness.call(
        deployment: context[:previous_deployment],
        executor_session: previous_executor_session,
        payload: { "close_request_id" => mailbox_item.public_id },
        mailbox_item: mailbox_item.reload,
        resource: process_run.reload,
        occurred_at: occurred_at
      )
    end
  end
end
