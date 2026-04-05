require "test_helper"

class AgentApiExecutionDeliveryTest < ActionDispatch::IntegrationTest
  test "execution_started accepts a leased assignment and establishes the holder lease" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    post "/program_api/control/report",
      params: {
        method_id: "execution_started",
        protocol_message_id: "agent-start-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        expected_duration_seconds: 30,
      },
      headers: program_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "running", agent_task_run.reload.lifecycle_state
    assert_equal context[:deployment], agent_task_run.holder_agent_program_version
  end

  test "execution_progress and execution_complete update durable task state through the public report api" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    post "/program_api/control/report",
      params: {
        method_id: "execution_started",
        protocol_message_id: "agent-start-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        expected_duration_seconds: 30,
      },
      headers: program_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")

    post "/program_api/control/report",
      params: {
        method_id: "execution_progress",
        protocol_message_id: "agent-progress-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        progress_payload: { "state" => "working", "percent" => 50 },
      },
      headers: program_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")
    assert_equal({ "state" => "working", "percent" => 50 }, agent_task_run.reload.progress_payload)
    assert_equal "running", agent_task_run.lifecycle_state
    assert agent_task_run.execution_lease.reload.active?

    post "/program_api/control/report",
      params: {
        method_id: "execution_complete",
        protocol_message_id: "agent-complete-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        terminal_payload: { "output" => "done" },
      },
      headers: program_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")

    agent_task_run.reload

    assert_equal "completed", agent_task_run.lifecycle_state
    assert_equal "done", agent_task_run.terminal_payload.fetch("output")
    assert_equal "execution_complete", agent_task_run.terminal_payload.fetch("terminal_method_id")
    assert_not_nil agent_task_run.finished_at
    assert_equal "completed", mailbox_item.reload.status
    assert_not_nil mailbox_item.completed_at
    assert_not agent_task_run.execution_lease.reload.active?
  end

  test "duplicate execution_complete is idempotent by protocol_message_id" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 30
    )

    params = {
      method_id: "execution_complete",
      protocol_message_id: "agent-complete-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: { "output" => "done" },
    }

    post "/program_api/control/report",
      params: params,
      headers: program_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    first_updated_at = agent_task_run.reload.updated_at

    post "/program_api/control/report",
      params: params,
      headers: program_api_headers(context[:machine_credential]),
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

    post "/program_api/control/report",
      params: {
        method_id: "execution_progress",
        protocol_message_id: "agent-progress-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: 1,
        progress_payload: { "state" => "late" },
      },
      headers: program_api_headers(context[:machine_credential]),
      as: :json

    assert_response :conflict
    assert_equal "stale", JSON.parse(response.body).fetch("result")
  end

  test "retryable execution failure moves the workflow into the step retry gate" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 30
    )

    post "/program_api/control/report",
      params: {
        method_id: "execution_fail",
        protocol_message_id: "agent-fail-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        terminal_payload: {
          "retryable" => true,
          "retry_scope" => "step",
          "failure_kind" => "tool_failure",
          "last_error_summary" => "exit status 1",
        },
      },
      headers: program_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "retryable_failure", workflow_run.wait_reason_kind
    assert_equal "step", workflow_run.wait_retry_scope
    assert_equal "tool_failure", workflow_run.wait_failure_kind
    assert_equal agent_task_run.attempt_no, workflow_run.wait_attempt_no
    assert_equal "exit status 1", workflow_run.wait_last_error_summary
    assert_equal({}, workflow_run.wait_reason_payload)
    assert_equal agent_task_run.public_id, workflow_run.blocking_resource_id
    assert context[:turn].reload.active?
  end

  test "execution progress is rejected once the turn has been fenced by interrupt" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 30
    )

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.current)

    post "/program_api/control/report",
      params: {
        method_id: "execution_progress",
        protocol_message_id: "agent-progress-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        progress_payload: { "state" => "late" },
      },
      headers: program_api_headers(context[:machine_credential]),
      as: :json

    assert_response :conflict
    assert_equal "stale", JSON.parse(response.body).fetch("result")
  end

  test "deployment_health_report refreshes control activity and piggybacks pending mailbox items" do
    context = build_agent_control_context!
    MailboxScenarioBuilder.new(self).execution_assignment!(context: context)

    post "/program_api/control/report",
      params: {
        method_id: "deployment_health_report",
        protocol_message_id: "health-#{next_test_sequence}",
        health_status: "healthy",
        health_metadata: { "source" => "runtime" },
      },
      headers: program_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    deployment = context[:deployment].reload

    assert_equal "active_control", deployment.control_activity_state
    assert_equal "healthy", deployment.health_status
    assert_equal 1, response_body.fetch("mailbox_items").size
  end
end
