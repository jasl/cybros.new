require "test_helper"

class AgentControl::ValidateCloseReportFreshnessTest < ActiveSupport::TestCase
  test "accepts fresh close reports for the leased execution session" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-03-29 20:30:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
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

    AgentControl::Poll.call(execution_session: context[:execution_session], limit: 10, occurred_at: occurred_at)

    result = AgentControl::ValidateCloseReportFreshness.call(
      deployment: context[:deployment],
      execution_session: context[:execution_session],
      payload: { "close_request_id" => mailbox_item.public_id },
      mailbox_item: mailbox_item.reload,
      resource: process_run.reload,
      occurred_at: occurred_at
    )

    assert_nil result
  end

  test "rejects close reports from the wrong execution session after leasing moved elsewhere" do
    context = build_rotated_runtime_context!
    occurred_at = Time.zone.parse("2026-03-29 20:45:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
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

    previous_execution_session = context.fetch(:registration).fetch(:execution_session)

    AgentControl::Poll.call(execution_session: context[:execution_session], limit: 10, occurred_at: occurred_at)

    assert_raises(AgentControl::Report::StaleReportError) do
      AgentControl::ValidateCloseReportFreshness.call(
        deployment: context[:previous_deployment],
        execution_session: previous_execution_session,
        payload: { "close_request_id" => mailbox_item.public_id },
        mailbox_item: mailbox_item.reload,
        resource: process_run.reload,
        occurred_at: occurred_at
      )
    end
  end
end
