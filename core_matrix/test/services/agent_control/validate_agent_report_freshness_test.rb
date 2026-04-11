require "test_helper"

class AgentControl::ValidateAgentReportFreshnessTest < ActiveSupport::TestCase
  test "accepts terminal agent reports for a leased mailbox item" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).agent_request!(
      context: context,
      request_kind: "prepare_round",
      payload: {
        "task" => {
          "kind" => "turn_step",
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
        },
      },
      logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}"
    )
    mailbox_item = scenario.fetch(:mailbox_item)
    AgentControl::Poll.call(agent_snapshot: context[:agent_snapshot], limit: 10)
    mailbox_item.reload

    assert_nothing_raised do
      AgentControl::ValidateAgentReportFreshness.call(
        agent_snapshot: context[:agent_snapshot],
        method_id: "agent_completed",
        mailbox_item: mailbox_item,
        payload: {
          "mailbox_item_id" => mailbox_item.public_id,
          "logical_work_id" => mailbox_item.logical_work_id,
          "attempt_no" => mailbox_item.attempt_no,
        }
      )
    end
  end

  test "rejects terminal agent reports once the mailbox lease has been superseded" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).agent_request!(
      context: context,
      request_kind: "prepare_round",
      payload: {
        "task" => {
          "kind" => "turn_step",
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
        },
      },
      logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}"
    )
    mailbox_item = scenario.fetch(:mailbox_item)
    AgentControl::Poll.call(agent_snapshot: context[:agent_snapshot], limit: 10)
    mailbox_item.reload.update!(status: "completed", completed_at: Time.current)

    assert_raises(AgentControl::Report::StaleReportError) do
      AgentControl::ValidateAgentReportFreshness.call(
        agent_snapshot: context[:agent_snapshot],
        method_id: "agent_completed",
        mailbox_item: mailbox_item,
        payload: {
          "mailbox_item_id" => mailbox_item.public_id,
          "logical_work_id" => mailbox_item.logical_work_id,
          "attempt_no" => mailbox_item.attempt_no,
        }
      )
    end
  end
end
