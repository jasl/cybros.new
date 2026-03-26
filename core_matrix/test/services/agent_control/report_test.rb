require "test_helper"

class AgentControlReportTest < ActiveSupport::TestCase
  test "execution_started acknowledges the offered delivery and acquires the task lease" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    result = AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_started",
      message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 15
    )

    assert_equal "accepted", result.code
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "running", agent_task_run.reload.lifecycle_state
    assert_equal context[:deployment], agent_task_run.holder_agent_deployment
    assert_equal context[:deployment].public_id, agent_task_run.execution_lease.holder_key
  end

  test "rejects stale reports from a superseded attempt" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context, attempt_no: 2)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    result = AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_progress",
      message_id: "agent-progress-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: 1,
      progress_payload: { "state" => "late" }
    )

    assert_equal "stale", result.code
    assert_equal({}, agent_task_run.reload.progress_payload)
  end

  test "rejects terminal close reports from a sibling deployment after another deployment acknowledged the request" do
    context = build_rotated_runtime_context!
    subagent_run = create_subagent_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running"
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: subagent_run
    ).fetch(:mailbox_item)

    assert_equal "agent_installation", mailbox_item.target_kind

    AgentControl::Poll.call(deployment: context[:replacement_deployment], limit: 10)

    ack_result = AgentControl::Report.call(
      deployment: context[:replacement_deployment],
      method_id: "resource_close_acknowledged",
      message_id: "close-ack-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      close_request_id: mailbox_item.public_id,
      resource_type: "SubagentRun",
      resource_id: subagent_run.public_id
    )

    assert_equal "accepted", ack_result.code
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "acknowledged", subagent_run.reload.close_state

    terminal_result = AgentControl::Report.call(
      deployment: context[:previous_deployment],
      method_id: "resource_closed",
      message_id: "close-terminal-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      close_request_id: mailbox_item.public_id,
      resource_type: "SubagentRun",
      resource_id: subagent_run.public_id,
      close_outcome_kind: "graceful",
      close_outcome_payload: {}
    )

    assert_equal "stale", terminal_result.code
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "acknowledged", subagent_run.reload.close_state
    assert subagent_run.reload.running?
  end
end
