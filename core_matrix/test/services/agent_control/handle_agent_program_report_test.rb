require "test_helper"

class AgentControl::HandleAgentProgramReportTest < ActiveSupport::TestCase
  test "accepts terminal agent program reports for a leased mailbox item" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).agent_program_request!(
      context: context,
      request_kind: "prepare_round",
      payload: {
        "workflow_node_id" => context.fetch(:workflow_node).public_id,
        "conversation_id" => context.fetch(:conversation).public_id,
        "turn_id" => context.fetch(:turn).public_id,
      },
      logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}"
    )
    mailbox_item = scenario.fetch(:mailbox_item)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    AgentControl::HandleAgentProgramReport.call(
      deployment: context[:deployment],
      method_id: "agent_program_completed",
      payload: {
        "mailbox_item_id" => mailbox_item.public_id,
        "logical_work_id" => mailbox_item.logical_work_id,
        "attempt_no" => mailbox_item.attempt_no,
      }
    )

    assert_equal "completed", mailbox_item.reload.status
    assert mailbox_item.completed_at.present?
  end

  test "rejects stale agent program reports after the mailbox lease expires" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).agent_program_request!(
      context: context,
      request_kind: "prepare_round",
      payload: {
        "workflow_node_id" => context.fetch(:workflow_node).public_id,
        "conversation_id" => context.fetch(:conversation).public_id,
        "turn_id" => context.fetch(:turn).public_id,
      },
      logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}"
    )
    mailbox_item = scenario.fetch(:mailbox_item)
    leased_at = Time.zone.parse("2026-03-31 10:00:00 UTC")

    travel_to(leased_at) do
      AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
    end

    assert_raises(AgentControl::Report::StaleReportError) do
      AgentControl::HandleAgentProgramReport.call(
        deployment: context[:deployment],
        method_id: "agent_program_completed",
        payload: {
          "mailbox_item_id" => mailbox_item.public_id,
          "logical_work_id" => mailbox_item.logical_work_id,
          "attempt_no" => mailbox_item.attempt_no,
        },
        occurred_at: leased_at + mailbox_item.lease_timeout_seconds.seconds + 1.second
      )
    end

    assert_equal "expired", mailbox_item.reload.status
  end
end
