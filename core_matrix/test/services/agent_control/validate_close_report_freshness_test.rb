require "test_helper"

class AgentControl::ValidateCloseReportFreshnessTest < ActiveSupport::TestCase
  test "accepts fresh close reports for the leased execution runtime connection" do
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

    AgentControl::Poll.call(execution_runtime_connection: context[:execution_runtime_connection], limit: 10, occurred_at: occurred_at)

    result = AgentControl::ValidateCloseReportFreshness.call(
      agent_definition_version: context[:agent_definition_version],
      execution_runtime_connection: context[:execution_runtime_connection],
      payload: { "close_request_id" => mailbox_item.public_id },
      mailbox_item: mailbox_item.reload,
      resource: process_run.reload,
      occurred_at: occurred_at
    )

    assert_nil result
  end

  test "rejects close reports from the wrong execution runtime connection after leasing moved elsewhere" do
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

    previous_execution_runtime_connection = context.fetch(:registration).fetch(:execution_runtime_connection)

    AgentControl::Poll.call(execution_runtime_connection: context[:execution_runtime_connection], limit: 10, occurred_at: occurred_at)

    assert_raises(AgentControl::Report::StaleReportError) do
      AgentControl::ValidateCloseReportFreshness.call(
        agent_definition_version: context[:previous_agent_definition_version],
        execution_runtime_connection: previous_execution_runtime_connection,
        payload: { "close_request_id" => mailbox_item.public_id },
        mailbox_item: mailbox_item.reload,
        resource: process_run.reload,
        occurred_at: occurred_at
      )
    end
  end
end
