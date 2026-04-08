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
        protocol_message_id: "agent-start-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        expected_duration_seconds: 30,
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "running", agent_task_run.reload.lifecycle_state
    assert_equal context[:deployment], agent_task_run.holder_agent_program_version
  end

  test "execution_started report stays under a request query budget" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    queries = capture_sql_queries do
      post "/agent_api/control/report",
        params: {
          method_id: "execution_started",
          protocol_message_id: "agent-start-budget-#{next_test_sequence}",
          mailbox_item_id: mailbox_item.public_id,
          agent_task_run_id: agent_task_run.public_id,
          logical_work_id: agent_task_run.logical_work_id,
          attempt_no: agent_task_run.attempt_no,
          expected_duration_seconds: 30,
        },
        headers: agent_api_headers(context[:machine_credential]),
        as: :json
    end

    assert_response :success
    assert_operator queries.length, :<=, 71, "Expected execution_started report to stay under 71 SQL queries, got #{queries.length}:\n#{queries.join("\n")}"
  end

  test "execution_progress and execution_complete update durable task state through the public report api" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    post "/agent_api/control/report",
      params: {
        method_id: "execution_started",
        protocol_message_id: "agent-start-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        expected_duration_seconds: 30,
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")

    post "/agent_api/control/report",
      params: {
        method_id: "execution_progress",
        protocol_message_id: "agent-progress-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        progress_payload: { "state" => "working", "percent" => 50 },
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")
    assert_equal({ "state" => "working", "percent" => 50 }, agent_task_run.reload.progress_payload)
    assert_equal "running", agent_task_run.lifecycle_state
    assert agent_task_run.execution_lease.reload.active?

    post "/agent_api/control/report",
      params: {
        method_id: "execution_complete",
        protocol_message_id: "agent-complete-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        terminal_payload: { "output" => "done" },
      },
      headers: agent_api_headers(context[:machine_credential]),
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

  test "agent_program_completed completes a leased mailbox request and reconstructs workflow refs through the public report api" do
    context = build_agent_control_context!
    mailbox_item = AgentControl::CreateAgentProgramRequest.call(
      agent_program_version: context.fetch(:deployment),
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
      logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}",
      dispatch_deadline_at: 5.minutes.from_now
    )
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
    protocol_message_id = "agent-program-complete-#{next_test_sequence}"

    post "/agent_api/control/report",
      params: {
        method_id: "agent_program_completed",
        protocol_message_id: protocol_message_id,
        mailbox_item_id: mailbox_item.public_id,
        logical_work_id: mailbox_item.logical_work_id,
        attempt_no: mailbox_item.attempt_no,
        response_payload: {
          "status" => "ok",
          "messages" => [],
          "visible_tool_names" => [],
          "summary_artifacts" => [],
          "trace" => [],
        },
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")
    assert_equal "completed", mailbox_item.reload.status
    assert_not_nil mailbox_item.completed_at

    receipt = AgentControlReportReceipt.find_by!(
      installation: context.fetch(:installation),
      protocol_message_id: protocol_message_id
    )

    assert_equal context.fetch(:conversation).public_id, receipt.payload.fetch("conversation_id")
    assert_equal context.fetch(:turn).public_id, receipt.payload.fetch("turn_id")
    assert_equal context.fetch(:workflow_node).public_id, receipt.payload.fetch("workflow_node_id")
    refute_includes response.body, %("#{context.fetch(:workflow_node).id}")
  end

  test "agent_program_failed fails a linked conversation control request through the public report api" do
    context = build_agent_control_context!
    supervision_session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "supervision_enabled" => true, "side_chat_enabled" => true, "control_enabled" => true },
      last_snapshot_at: Time.current
    )
    control_request = ConversationControlRequest.create!(
      installation: context[:installation],
      conversation_supervision_session: supervision_session,
      target_conversation: context[:conversation],
      request_kind: "send_guidance_to_active_agent",
      target_kind: "conversation",
      target_public_id: context[:conversation].public_id,
      lifecycle_state: "queued",
      request_payload: { "content" => "Stop and summarize." },
      result_payload: {}
    )
    mailbox_item = AgentControl::CreateConversationControlRequest.call(
      conversation_control_request: control_request,
      agent_program_version: context[:deployment],
      request_kind: "supervision_guidance",
      payload: { "content" => "Stop and summarize." },
      dispatch_deadline_at: 5.minutes.from_now
    )
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    post "/agent_api/control/report",
      params: {
        method_id: "agent_program_failed",
        protocol_message_id: "agent-program-failed-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        logical_work_id: mailbox_item.logical_work_id,
        attempt_no: mailbox_item.attempt_no,
        error_payload: {
          "classification" => "runtime",
          "code" => "program_request_failed",
          "message" => "guidance could not be delivered",
          "retryable" => false,
        },
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")
    assert_equal "failed", mailbox_item.reload.status
    assert_equal "failed", control_request.reload.lifecycle_state
    assert_equal mailbox_item.public_id, control_request.result_payload.fetch("mailbox_item_id")
    assert_equal "failed", control_request.result_payload.fetch("mailbox_status")
    assert_equal "program_request_failed", control_request.result_payload.dig("error_payload", "code")
  end

  test "agent_program_completed persists structured supervision response payloads on the linked control request" do
    context = build_agent_control_context!
    supervision_session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "supervision_enabled" => true, "side_chat_enabled" => true, "control_enabled" => true },
      last_snapshot_at: Time.current
    )
    control_request = ConversationControlRequest.create!(
      installation: context[:installation],
      conversation_supervision_session: supervision_session,
      target_conversation: context[:conversation],
      request_kind: "request_status_refresh",
      target_kind: "conversation",
      target_public_id: context[:conversation].public_id,
      lifecycle_state: "queued",
      request_payload: {},
      result_payload: {}
    )
    mailbox_item = AgentControl::CreateConversationControlRequest.call(
      conversation_control_request: control_request,
      agent_program_version: context[:deployment],
      request_kind: "supervision_status_refresh",
      payload: {},
      dispatch_deadline_at: 5.minutes.from_now
    )
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    post "/agent_api/control/report",
      params: {
        method_id: "agent_program_completed",
        protocol_message_id: "agent-program-supervision-complete-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        logical_work_id: mailbox_item.logical_work_id,
        attempt_no: mailbox_item.attempt_no,
        response_payload: {
          "status" => "ok",
          "control_outcome" => {
            "outcome_kind" => "status_refresh_acknowledged",
            "conversation_control_request_id" => control_request.public_id,
            "conversation_id" => context[:conversation].public_id,
            "target_kind" => "conversation",
            "target_public_id" => context[:conversation].public_id,
          },
        },
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")
    assert_equal "completed", control_request.reload.lifecycle_state
    assert_equal "status_refresh_acknowledged",
      control_request.result_payload.dig("response_payload", "control_outcome", "outcome_kind")
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
        protocol_message_id: "agent-progress-#{next_test_sequence}",
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

    post "/agent_api/control/report",
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
      headers: agent_api_headers(context[:machine_credential]),
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

    post "/agent_api/control/report",
      params: {
        method_id: "execution_progress",
        protocol_message_id: "agent-progress-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
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
        protocol_message_id: "health-#{next_test_sequence}",
        health_status: "healthy",
        health_metadata: { "source" => "runtime" },
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    deployment = context[:deployment].reload

    assert_equal "active_control", deployment.control_activity_state
    assert_equal "healthy", deployment.health_status
    assert_equal 1, response_body.fetch("mailbox_items").size
  end
end
