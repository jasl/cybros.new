require "test_helper"

class AgentControl::ValidateExecutionReportFreshnessTest < ActiveSupport::TestCase
  test "accepts a fresh execution_started offer for the leased queued attempt" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    result = AgentControl::ValidateExecutionReportFreshness.call(
      deployment: context[:deployment],
      method_id: "execution_started",
      payload: {
        "logical_work_id" => agent_task_run.logical_work_id,
        "attempt_no" => agent_task_run.attempt_no,
      },
      mailbox_item: mailbox_item.reload,
      agent_task_run: agent_task_run.reload,
      occurred_at: Time.current
    )

    assert_nil result
  end

  test "rejects active execution reports once the task is already closing" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    started_at = Time.zone.parse("2026-03-29 21:00:00 UTC")
    agent_task_run = scenario.fetch(:agent_task_run)
    agent_task_run.update!(
      lifecycle_state: "running",
      holder_agent_session: context[:agent_session],
      close_state: "requested",
      close_reason_kind: "operator_stop",
      close_requested_at: Time.current,
      started_at: started_at
    )
    Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )

    assert_raises(AgentControl::Report::StaleReportError) do
      AgentControl::ValidateExecutionReportFreshness.call(
        deployment: context[:deployment],
        method_id: "execution_progress",
        payload: {
          "logical_work_id" => agent_task_run.logical_work_id,
          "attempt_no" => agent_task_run.attempt_no,
        },
        mailbox_item: scenario.fetch(:mailbox_item),
        agent_task_run: agent_task_run.reload,
        occurred_at: Time.current
      )
    end
  end
end
