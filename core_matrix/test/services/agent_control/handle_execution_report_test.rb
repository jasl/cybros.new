require "test_helper"

class AgentControl::HandleExecutionReportTest < ActiveSupport::TestCase
  test "maps stale heartbeat timeouts to stale reports without mutating execution progress" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    started_at = Time.zone.parse("2026-03-29 22:00:00 UTC")

    travel_to(started_at) do
      agent_task_run.update!(
        lifecycle_state: "running",
        holder_agent_session: context[:agent_session],
        started_at: started_at
      )
      Leases::Acquire.call(
        leased_resource: agent_task_run,
        holder_key: context[:deployment].public_id,
        heartbeat_timeout_seconds: 30
      )
      mailbox_item.update!(
        status: "acked",
        leased_to_agent_session: context[:agent_session],
        leased_at: started_at,
        lease_expires_at: started_at + mailbox_item.lease_timeout_seconds.seconds,
        acked_at: started_at
      )
    end

    assert_raises(AgentControl::Report::StaleReportError) do
      AgentControl::HandleExecutionReport.call(
        deployment: context[:deployment],
        method_id: "execution_progress",
        payload: {
          "mailbox_item_id" => mailbox_item.public_id,
          "agent_task_run_id" => agent_task_run.public_id,
          "logical_work_id" => agent_task_run.logical_work_id,
          "attempt_no" => agent_task_run.attempt_no,
          "progress_payload" => { "state" => "late" },
        },
        occurred_at: started_at + 31.seconds
      )
    end

    assert_equal({}, agent_task_run.reload.progress_payload)
    assert_equal "running", agent_task_run.lifecycle_state
    assert_equal "heartbeat_timeout", agent_task_run.execution_lease.reload.release_reason
    assert_not agent_task_run.execution_lease.active?
    assert_equal "acked", mailbox_item.reload.status
  end
end
