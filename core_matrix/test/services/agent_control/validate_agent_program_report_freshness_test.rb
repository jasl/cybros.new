require "test_helper"

class AgentControl::ValidateAgentProgramReportFreshnessTest < ActiveSupport::TestCase
  test "accepts terminal agent program reports for a leased mailbox item" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).agent_program_request!(
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
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
    mailbox_item.reload

    assert_nothing_raised do
      AgentControl::ValidateAgentProgramReportFreshness.call(
        deployment: context[:deployment],
        method_id: "agent_program_completed",
        mailbox_item: mailbox_item,
        payload: {
          "mailbox_item_id" => mailbox_item.public_id,
          "logical_work_id" => mailbox_item.logical_work_id,
          "attempt_no" => mailbox_item.attempt_no,
        }
      )
    end
  end

  test "rejects terminal agent program reports once the mailbox lease has been superseded" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).agent_program_request!(
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
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
    mailbox_item.reload.update!(status: "completed", completed_at: Time.current)

    assert_raises(AgentControl::Report::StaleReportError) do
      AgentControl::ValidateAgentProgramReportFreshness.call(
        deployment: context[:deployment],
        method_id: "agent_program_completed",
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
