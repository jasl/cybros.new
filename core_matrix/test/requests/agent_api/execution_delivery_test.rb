require "test_helper"

class AgentApiExecutionDeliveryTest < ActionDispatch::IntegrationTest
  test "execution_started accepts a leased assignment and establishes the holder lease" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    post "/agent_api/control/report",
      params: {
        method_id: "execution_started",
        message_id: "agent-start-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        expected_duration_seconds: 30,
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "running", agent_task_run.reload.lifecycle_state
    assert_equal context[:deployment], agent_task_run.holder_agent_deployment
  end

  test "duplicate execution_complete is idempotent by message_id" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_started",
      message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 30
    )

    params = {
      method_id: "execution_complete",
      message_id: "agent-complete-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: { "output" => "done" },
    }

    post "/agent_api/control/report",
      params: params,
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    first_updated_at = agent_task_run.reload.updated_at

    post "/agent_api/control/report",
      params: params,
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    response_body = JSON.parse(response.body)

    assert_equal "duplicate", response_body.fetch("result")
    assert_equal first_updated_at, agent_task_run.reload.updated_at
  end

  test "stale execution progress is rejected once the task attempt has been superseded" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context, attempt_no: 2)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    post "/agent_api/control/report",
      params: {
        method_id: "execution_progress",
        message_id: "agent-progress-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: 1,
        progress_payload: { "state" => "late" },
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :conflict
    assert_equal "stale", JSON.parse(response.body).fetch("result")
  end

  test "deployment_health_report refreshes control activity and piggybacks pending mailbox items" do
    context = build_agent_control_context!
    MailboxScenarioBuilder.new(self).execution_assignment!(context: context)

    post "/agent_api/control/report",
      params: {
        method_id: "deployment_health_report",
        message_id: "health-#{next_test_sequence}",
        health_status: "healthy",
        health_metadata: { "source" => "runtime" },
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    deployment = context[:deployment].reload

    assert_equal "active", deployment.control_activity_state
    assert_equal "healthy", deployment.health_status
    assert_equal 1, response_body.fetch("mailbox_items").size
  end
end
