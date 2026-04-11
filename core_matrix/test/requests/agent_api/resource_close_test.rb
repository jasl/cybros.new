require "test_helper"

class AgentApiResourceCloseTest < ActionDispatch::IntegrationTest
  test "resource close acknowledgement and terminal close outcome update durable close fields" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:agent_snapshot].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(execution_runtime_connection: context[:execution_runtime_connection], limit: 10)

    post "/execution_runtime_api/control/report",
      params: {
        method_id: "resource_close_acknowledged",
        protocol_message_id: "close-ack-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        close_request_id: mailbox_item.public_id,
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
      },
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")
    assert_equal "acknowledged", process_run.reload.close_state

    post "/execution_runtime_api/control/report",
      params: {
        method_id: "resource_closed",
        protocol_message_id: "close-terminal-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        close_request_id: mailbox_item.public_id,
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
        close_outcome_kind: "graceful",
        close_outcome_payload: { "signal" => "SIGINT" },
      },
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")

    process_run.reload
    assert_equal "closed", process_run.close_state
    assert_equal "graceful", process_run.close_outcome_kind
    assert_equal "completed", mailbox_item.reload.status
  end

  test "resource_close_acknowledged report stays under an execution-runtime-plane request query budget" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:agent_snapshot].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(execution_runtime_connection: context[:execution_runtime_connection], limit: 10)

    queries = capture_sql_queries do
      post "/execution_runtime_api/control/report",
        params: {
          method_id: "resource_close_acknowledged",
          protocol_message_id: "close-ack-budget-#{next_test_sequence}",
          mailbox_item_id: mailbox_item.public_id,
          close_request_id: mailbox_item.public_id,
          resource_type: "ProcessRun",
          resource_id: process_run.public_id,
        },
        headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
        as: :json
    end

    assert_response :success
    assert_operator queries.length, :<=, 35, "Expected resource_close_acknowledged report to stay under 35 SQL queries, got #{queries.length}:\n#{queries.join("\n")}"
  end

  test "duplicate resource_closed is idempotent by protocol_message_id" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:agent_snapshot].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(execution_runtime_connection: context[:execution_runtime_connection], limit: 10)

    params = {
      method_id: "resource_closed",
      protocol_message_id: "close-terminal-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      close_request_id: mailbox_item.public_id,
      resource_type: "ProcessRun",
      resource_id: process_run.public_id,
      close_outcome_kind: "forced",
      close_outcome_payload: { "signal" => "SIGKILL" },
    }

    post "/execution_runtime_api/control/report",
      params: params,
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :success
    first_updated_at = process_run.reload.updated_at

    post "/execution_runtime_api/control/report",
      params: params,
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :success
    assert_equal "duplicate", JSON.parse(response.body).fetch("result")
    assert_equal first_updated_at, process_run.reload.updated_at
  end

  test "resource_close_acknowledged uses server receive time for freshness instead of a client supplied occurred_at" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-03-28 14:00:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:agent_snapshot].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = travel_to(occurred_at) do
      MailboxScenarioBuilder.new(self).close_request!(
        context: context,
        resource: process_run
      ).fetch(:mailbox_item)
    end

    travel_to(occurred_at) do
      AgentControl::Poll.call(execution_runtime_connection: context[:execution_runtime_connection], limit: 10)
    end

    travel_to(occurred_at + 31.seconds) do
      post "/execution_runtime_api/control/report",
        params: {
          method_id: "resource_close_acknowledged",
          protocol_message_id: "close-ack-stale-#{next_test_sequence}",
          mailbox_item_id: mailbox_item.public_id,
          close_request_id: mailbox_item.public_id,
          resource_type: "ProcessRun",
          resource_id: process_run.public_id,
          occurred_at: occurred_at.iso8601,
        },
        headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
        as: :json
    end

    assert_response :conflict
    assert_equal "stale", JSON.parse(response.body).fetch("result")
    assert_equal "requested", process_run.reload.close_state
    assert_equal "leased", mailbox_item.reload.status
    assert_equal context[:execution_runtime_connection].public_id, mailbox_item.leased_to_execution_runtime_connection.public_id
  end

  test "resource_closed rejects wrong-environment reporters even when payload data is spoofed" do
    context = build_agent_control_context!
    other_agent = create_agent!(installation: context[:installation])
    other_execution_runtime = create_execution_runtime!(installation: context[:installation])
    wrong_runtime = register_agent_runtime!(
      installation: context[:installation],
      actor: context[:actor],
      agent: other_agent,
      execution_runtime: other_execution_runtime,
      reuse_enrollment: true
    )
    wrong_runtime.fetch(:agent_connection).update!(
      health_status: "healthy",
      last_heartbeat_at: Time.current,
      last_health_check_at: Time.current
    )
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:agent_snapshot].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)

    assert mailbox_item.execution_runtime_plane?

    AgentControl::Poll.call(execution_runtime_connection: context[:execution_runtime_connection], limit: 10)

    post "/execution_runtime_api/control/report",
      params: {
        method_id: "resource_closed",
        protocol_message_id: "close-spoofed-env-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        close_request_id: mailbox_item.public_id,
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
        control_plane: "invalid",
        execution_runtime_id: context[:execution_runtime].public_id,
        close_outcome_kind: "graceful",
        close_outcome_payload: { "signal" => "SIGINT" },
      },
      headers: execution_runtime_api_headers(wrong_runtime.fetch(:execution_runtime_connection_credential)),
      as: :json

    assert_response :not_found
    assert_equal "Couldn't find ProcessRun", JSON.parse(response.body).fetch("error")
    assert_equal "requested", process_run.reload.close_state
    assert_equal "leased", mailbox_item.reload.status
    assert_equal context[:execution_runtime_connection].public_id, mailbox_item.reload.leased_to_execution_runtime_connection.public_id
  end

  test "resource_closed terminalizes an agent task run, interrupts running command runs, and releases its execution lease" do
    context = build_exec_command_runtime_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )
    command_run = create_running_command_run!(agent_task_run)
    invocation = command_run.tool_invocation
    lease = Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: context[:agent_snapshot].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: agent_task_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(agent_snapshot: context[:agent_snapshot], limit: 10)

    post "/agent_api/control/report",
      params: {
        method_id: "resource_closed",
        protocol_message_id: "task-close-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        close_request_id: mailbox_item.public_id,
        resource_type: "AgentTaskRun",
        resource_id: agent_task_run.public_id,
        close_outcome_kind: "graceful",
        close_outcome_payload: { "signal" => "interrupt" },
      },
      headers: agent_api_headers(context[:agent_connection_credential]),
      as: :json

    assert_response :success

    agent_task_run.reload
    assert_equal "interrupted", agent_task_run.lifecycle_state
    assert_not_nil agent_task_run.finished_at
    assert_equal "closed", agent_task_run.close_state
    assert command_run.reload.interrupted?
    assert invocation.reload.canceled?
    assert_equal "canceled", context[:workflow_node].reload.lifecycle_state
    assert_not_nil context[:workflow_node].finished_at
    assert_not lease.reload.active?
  end

  test "resource_close_failed marks an agent task run failed and fails running command runs" do
    context = build_exec_command_runtime_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )
    command_run = create_running_command_run!(agent_task_run)
    invocation = command_run.tool_invocation
    lease = Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: context[:agent_snapshot].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: agent_task_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(agent_snapshot: context[:agent_snapshot], limit: 10)

    post "/agent_api/control/report",
      params: {
        method_id: "resource_close_failed",
        protocol_message_id: "task-close-failed-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        close_request_id: mailbox_item.public_id,
        resource_type: "AgentTaskRun",
        resource_id: agent_task_run.public_id,
        close_outcome_kind: "timed_out_forced",
        close_outcome_payload: { "signal" => "SIGKILL", "timeout" => true },
      },
      headers: agent_api_headers(context[:agent_connection_credential]),
      as: :json

    assert_response :success

    agent_task_run.reload
    assert_equal "failed", agent_task_run.lifecycle_state
    assert_not_nil agent_task_run.finished_at
    assert_equal "failed", agent_task_run.close_state
    assert_equal "timed_out_forced", agent_task_run.terminal_payload["close_outcome_kind"]
    assert command_run.reload.failed?
    assert invocation.reload.failed?
    assert_equal "failed", context[:workflow_node].reload.lifecycle_state
    assert_not_nil context[:workflow_node].finished_at
    assert_not lease.reload.active?
  end

  test "resource_close_failed marks a process run lost instead of stopped" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
    )
    lease = Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:execution_runtime_connection].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(execution_runtime_connection: context[:execution_runtime_connection], limit: 10)

    post "/execution_runtime_api/control/report",
      params: {
        method_id: "resource_close_failed",
        protocol_message_id: "process-close-failed-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        close_request_id: mailbox_item.public_id,
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
        close_outcome_kind: "timed_out_forced",
        close_outcome_payload: { "signal" => "SIGKILL", "timeout" => true },
      },
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :success

    process_run.reload
    assert_equal "lost", process_run.lifecycle_state
    assert_equal "failed", process_run.close_state
    assert_equal "timed_out_forced", process_run.close_outcome_kind
    assert_not lease.reload.active?
  end

  test "residual process close leaves the process run lost instead of stopped" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:execution_runtime_connection].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(execution_runtime_connection: context[:execution_runtime_connection], limit: 10)

    post "/execution_runtime_api/control/report",
      params: {
        method_id: "resource_closed",
        protocol_message_id: "process-close-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        close_request_id: mailbox_item.public_id,
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
        close_outcome_kind: "residual_abandoned",
        close_outcome_payload: { "signal" => "SIGKILL", "residual" => true },
      },
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :success

    process_run.reload
    assert_equal "lost", process_run.lifecycle_state
    assert_equal "residual_abandoned", process_run.close_outcome_kind
  end

  test "resource_closed accepts the shared process close report fixture through the public report api" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:agent_snapshot].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(execution_runtime_connection: context[:execution_runtime_connection], limit: 10)

    report = resource_closed_report_fixture.deep_dup.merge(
      "mailbox_item_id" => mailbox_item.public_id,
      "close_request_id" => mailbox_item.public_id,
      "resource_id" => process_run.public_id
    )

    post "/execution_runtime_api/control/report",
      params: report.merge("protocol_message_id" => "resource-close-contract-#{next_test_sequence}"),
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")
    assert_equal "closed", process_run.reload.close_state
    assert_equal "graceful", process_run.close_outcome_kind
    assert_equal "completed", mailbox_item.reload.status
  end

  private

  def resource_closed_report_fixture
    JSON.parse(
      File.read(
        Rails.root.join("..", "shared", "fixtures", "contracts", "fenix_resource_closed_report.json")
      )
    )
  end

  def build_exec_command_runtime_context!
    build_governed_tool_context!(
      execution_runtime_tool_catalog: [],
      agent_tool_catalog: [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "kernel_primitive",
          "implementation_source" => "agent",
          "implementation_ref" => "agent/exec_command",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => true,
          "idempotency_policy" => "best_effort",
        },
      ],
      profile_catalog: {
        "main" => {
          "label" => "Main",
          "description" => "Primary interactive profile",
          "allowed_tool_names" => ["exec_command"],
        },
      }
    )
  end

  def create_running_command_run!(agent_task_run)
    binding = agent_task_run.reload.tool_bindings.joins(:tool_definition).find_by!(
      tool_definitions: { tool_name: "exec_command" }
    )
    invocation = ToolInvocations::Start.call(
      tool_binding: binding,
      request_payload: {
        "tool_name" => "exec_command",
        "command_line" => "sleep 30",
      },
      idempotency_key: "tool-call-#{next_test_sequence}",
      stream_output: true
    )

    command_run = CommandRuns::Provision.call(
      tool_invocation: invocation,
      command_line: "sleep 30",
      timeout_seconds: 30,
      pty: false,
      metadata: {}
    ).command_run
    CommandRuns::Activate.call(command_run: command_run)
    command_run
  end
end
