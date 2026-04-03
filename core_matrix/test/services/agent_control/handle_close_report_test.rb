require "test_helper"

class AgentControl::HandleCloseReportTest < ActiveSupport::TestCase
  test "treats close reports as stale once the leased mailbox offer has expired" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-03-29 22:30:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:execution_session].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = travel_to(occurred_at) do
      MailboxScenarioBuilder.new(self).close_request!(
        context: context,
        resource: process_run
      ).fetch(:mailbox_item)
    end

    AgentControl::Poll.call(execution_session: context[:execution_session], limit: 10, occurred_at: occurred_at)

    assert_raises(AgentControl::Report::StaleReportError) do
      AgentControl::HandleCloseReport.call(
        deployment: context[:deployment],
        execution_session: context[:execution_session],
        method_id: "resource_close_acknowledged",
        payload: {
          "mailbox_item_id" => mailbox_item.public_id,
          "close_request_id" => mailbox_item.public_id,
          "resource_type" => "ProcessRun",
          "resource_id" => process_run.public_id,
        },
        occurred_at: occurred_at + mailbox_item.lease_timeout_seconds.seconds + 1.second
      )
    end

    assert_equal "requested", process_run.reload.close_state
    assert_equal "leased", mailbox_item.reload.status
    assert_equal context[:execution_session].public_id, mailbox_item.leased_to_execution_session.public_id
  end
end
