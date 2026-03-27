require "test_helper"

class AgentApiResourceCloseTest < ActionDispatch::IntegrationTest
  test "resource close acknowledgement and terminal close outcome update durable close fields" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    post "/agent_api/control/report",
      params: {
        method_id: "resource_close_acknowledged",
        message_id: "close-ack-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        close_request_id: mailbox_item.public_id,
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")
    assert_equal "acknowledged", process_run.reload.close_state

    post "/agent_api/control/report",
      params: {
        method_id: "resource_closed",
        message_id: "close-terminal-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        close_request_id: mailbox_item.public_id,
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
        close_outcome_kind: "graceful",
        close_outcome_payload: { "signal" => "SIGINT" },
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")

    process_run.reload
    assert_equal "closed", process_run.close_state
    assert_equal "graceful", process_run.close_outcome_kind
    assert_equal "completed", mailbox_item.reload.status
  end

  test "duplicate resource_closed is idempotent by message_id" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    params = {
      method_id: "resource_closed",
      message_id: "close-terminal-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      close_request_id: mailbox_item.public_id,
      resource_type: "ProcessRun",
      resource_id: process_run.public_id,
      close_outcome_kind: "forced",
      close_outcome_payload: { "signal" => "SIGKILL" },
    }

    post "/agent_api/control/report",
      params: params,
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    first_updated_at = process_run.reload.updated_at

    post "/agent_api/control/report",
      params: params,
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success
    assert_equal "duplicate", JSON.parse(response.body).fetch("result")
    assert_equal first_updated_at, process_run.reload.updated_at
  end

  test "resource_closed rejects wrong-environment reporters even when payload data is spoofed" do
    context = build_agent_control_context!
    other_agent_installation = create_agent_installation!(installation: context[:installation])
    other_execution_environment = create_execution_environment!(installation: context[:installation])
    wrong_runtime = register_agent_runtime!(
      installation: context[:installation],
      actor: context[:actor],
      agent_installation: other_agent_installation,
      execution_environment: other_execution_environment,
      reuse_enrollment: true
    )
    wrong_runtime.fetch(:deployment).update!(
      bootstrap_state: "active",
      health_status: "healthy",
      last_heartbeat_at: Time.current
    )
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)

    assert mailbox_item.environment_plane?

    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    post "/agent_api/control/report",
      params: {
        method_id: "resource_closed",
        message_id: "close-spoofed-env-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        close_request_id: mailbox_item.public_id,
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
        runtime_plane: "environment",
        execution_environment_id: context[:execution_environment].public_id,
        target_ref: context[:execution_environment].public_id,
        close_outcome_kind: "graceful",
        close_outcome_payload: { "signal" => "SIGINT" },
      },
      headers: agent_api_headers(wrong_runtime.fetch(:machine_credential)),
      as: :json

    assert_response :conflict
    assert_equal "stale", JSON.parse(response.body).fetch("result")
    assert_equal "requested", process_run.reload.close_state
    assert_equal "leased", mailbox_item.reload.status
    assert_equal context[:deployment].public_id, mailbox_item.reload.leased_to_agent_deployment.public_id
  end

  test "resource_closed terminalizes an agent task run and releases its execution lease" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )
    lease = Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: agent_task_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    post "/agent_api/control/report",
      params: {
        method_id: "resource_closed",
        message_id: "task-close-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        close_request_id: mailbox_item.public_id,
        resource_type: "AgentTaskRun",
        resource_id: agent_task_run.public_id,
        close_outcome_kind: "graceful",
        close_outcome_payload: { "signal" => "interrupt" },
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success

    agent_task_run.reload
    assert_equal "interrupted", agent_task_run.lifecycle_state
    assert_not_nil agent_task_run.finished_at
    assert_equal "closed", agent_task_run.close_state
    assert_not lease.reload.active?
  end

  test "residual process close leaves the process run lost instead of stopped" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    post "/agent_api/control/report",
      params: {
        method_id: "resource_closed",
        message_id: "process-close-#{next_test_sequence}",
        mailbox_item_id: mailbox_item.public_id,
        close_request_id: mailbox_item.public_id,
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
        close_outcome_kind: "residual_abandoned",
        close_outcome_payload: { "signal" => "SIGKILL", "residual" => true },
      },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success

    process_run.reload
    assert_equal "lost", process_run.lifecycle_state
    assert_equal "residual_abandoned", process_run.close_outcome_kind
  end
end
