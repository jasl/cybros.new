require "test_helper"
require "active_job/test_helper"

class Fenix::Runtime::MailboxWorkerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  RuntimeControlClientDouble = Struct.new(:reported_payloads, keyword_init: true) do
    def report!(payload:)
      reported_payloads << payload.deep_dup
      { "result" => "accepted" }
    end
  end

  setup do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
    Fenix::Shared::Values::MailboxDeliveryTracker.reset!
    @original_control_plane_client =
      if Fenix::Shared::ControlPlane.instance_variable_defined?(:@client)
        Fenix::Shared::ControlPlane.instance_variable_get(:@client)
      else
        :__undefined__
      end
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    Fenix::ExecutionRuntime::Processes::Manager.reset!
    Fenix::ExecutionRuntime::Processes::ProxyRegistry.reset!
    Fenix::Shared::Values::MailboxDeliveryTracker.reset!

    if @original_control_plane_client == :__undefined__
      Fenix::Shared::ControlPlane.remove_instance_variable(:@client) if Fenix::Shared::ControlPlane.instance_variable_defined?(:@client)
    else
      Fenix::Shared::ControlPlane.client = @original_control_plane_client
    end
  end

  test "agent task close requests emit close lifecycle reports" do
    client = build_control_client

    result = Fenix::Runtime::MailboxWorker.call(
      mailbox_item: close_request(resource_type: "AgentTaskRun", resource_id: "task-1"),
      deliver_reports: true,
      control_client: client
    )

    assert_equal :handled, result
    assert_equal %w[resource_close_acknowledged resource_closed], client.reported_payloads.map { |payload| payload.fetch("method_id") }
  end

  test "subagent connection close requests emit close lifecycle reports" do
    client = build_control_client

    result = Fenix::Runtime::MailboxWorker.call(
      mailbox_item: close_request(resource_type: "SubagentConnection", resource_id: "subagent-1"),
      deliver_reports: true,
      control_client: client
    )

    assert_equal :handled, result
    assert_equal %w[resource_close_acknowledged resource_closed], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "SubagentConnection", client.reported_payloads.last.fetch("resource_type")
  end

  test "close requests without report delivery do not require a configured control plane" do
    result = Fenix::Runtime::MailboxWorker.call(
      mailbox_item: close_request(resource_type: "AgentTaskRun", resource_id: "task-1"),
      deliver_reports: false
    )

    assert_equal :handled, result
  end

  test "process run close requests report failure when the local handle is missing" do
    client = build_control_client

    result = Fenix::Runtime::MailboxWorker.call(
      mailbox_item: close_request(resource_type: "ProcessRun", resource_id: "process-1"),
      deliver_reports: true,
      control_client: client
    )

    assert_equal :handled, result
    assert_equal ["resource_close_failed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "ProcessRun", client.reported_payloads.last.fetch("resource_type")
  end

  test "process run close requests are delegated to the local process manager when a durable process is present" do
    client = build_control_client
    process_run_id = "process-#{SecureRandom.uuid}"

    Fenix::ExecutionRuntime::Processes::Manager.spawn!(
      process_run_id: process_run_id,
      runtime_owner_id: "task-1",
      command_line: "trap 'exit 0' TERM; while :; do sleep 1; done",
      control_client: client
    )

    assert_eventually do
      client.reported_payloads.any? { |payload| payload["method_id"] == "process_started" && payload["resource_id"] == process_run_id }
    end

    result = Fenix::Runtime::MailboxWorker.call(
      mailbox_item: close_request(resource_type: "ProcessRun", resource_id: process_run_id),
      deliver_reports: true,
      control_client: client
    )

    assert_equal :handled, result

    assert_eventually do
      client.reported_payloads.any? { |payload| payload["method_id"] == "resource_closed" && payload["resource_id"] == process_run_id }
    end

    method_ids = client.reported_payloads
      .select { |payload| payload["resource_id"] == process_run_id }
      .map { |payload| payload.fetch("method_id") }

    assert_includes method_ids, "resource_close_acknowledged"
    assert_includes method_ids, "resource_closed"
  end

  test "non-inline executable mailbox items enqueue the runtime mailbox job" do
    Fenix::Shared::ControlPlane.client = build_control_client
    mailbox_item = execution_assignment_mailbox_item

    result = nil

    assert_enqueued_with(job: Fenix::Runtime::MailboxExecutionJob) do
      result = Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item, inline: false)
    end

    assert_equal "queued", result.status
    assert_equal mailbox_item.fetch("item_id"), result.mailbox_item_id
  end

  test "queued executable mailbox items are settled by the runtime mailbox job" do
    client = build_control_client
    Fenix::Shared::ControlPlane.client = client
    mailbox_item = execution_assignment_mailbox_item

    assert_enqueued_with(job: Fenix::Runtime::MailboxExecutionJob) do
      Fenix::Runtime::MailboxWorker.call(
        mailbox_item: mailbox_item,
        deliver_reports: true,
        inline: false
      )
    end

    perform_enqueued_jobs

    assert_equal ["execution_started", "execution_fail"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal 30, client.reported_payloads.first.fetch("expected_duration_seconds")
    assert_equal mailbox_item.fetch("item_id"), client.reported_payloads.last.fetch("mailbox_item_id")
  end

  test "non-inline executable mailbox items ignore duplicate deliveries for the same mailbox item" do
    Fenix::Shared::ControlPlane.client = build_control_client
    mailbox_item = execution_assignment_mailbox_item

    assert_enqueued_jobs 1 do
      Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item, inline: false)
      Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item.deep_dup, inline: false)
    end
  end

  test "non-inline executable mailbox items allow redelivery when delivery number increases" do
    Fenix::Shared::ControlPlane.client = build_control_client
    mailbox_item = execution_assignment_mailbox_item

    assert_enqueued_jobs 2 do
      Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item, inline: false)
      Fenix::Runtime::MailboxWorker.call(
        mailbox_item: mailbox_item.deep_dup.merge("delivery_no" => 2),
        inline: false
      )
    end
  end

  test "queued executable mailbox items serialize control plane context for out-of-process execution" do
    client = Fenix::Shared::ControlPlane::Client.new(
      base_url: "https://core-matrix.example.test",
      agent_connection_credential: "program-secret"
    )
    mailbox_item = execution_assignment_mailbox_item

    assert_enqueued_with(job: Fenix::Runtime::MailboxExecutionJob) do
      Fenix::Runtime::MailboxWorker.call(
        mailbox_item: mailbox_item,
        deliver_reports: true,
        control_client: client,
        inline: false
      )
    end

    serialized_context = enqueued_jobs.last.fetch(:args).second.fetch("control_plane_context")

    assert_equal "https://core-matrix.example.test", serialized_context.fetch("base_url")
    assert_equal "program-secret", serialized_context.fetch("agent_connection_credential")
  end

  test "inline executable mailbox items emit terminal failure reports" do
    client = build_control_client
    mailbox_item = execution_assignment_mailbox_item

    result = Fenix::Runtime::MailboxWorker.call(
      mailbox_item: mailbox_item,
      deliver_reports: true,
      control_client: client,
      inline: true
    )

    assert_equal "failed", result.fetch("status")
    assert_equal ["execution_started", "execution_fail"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal 30, client.reported_payloads.first.fetch("expected_duration_seconds")
    assert_equal "invalid_deterministic_tool_request", client.reported_payloads.last.dig("terminal_payload", "code")
  end

  private

  def build_control_client
    RuntimeControlClientDouble.new(reported_payloads: [])
  end

  def close_request(resource_type:, resource_id:)
    {
      "item_type" => "resource_close_request",
      "item_id" => "mailbox-item-close-#{resource_id}",
      "logical_work_id" => "logical-work-close-#{resource_id}",
      "attempt_no" => 1,
      "control_plane" => "agent",
      "payload" => {
        "resource_type" => resource_type,
        "resource_id" => resource_id,
      },
    }
  end

  def execution_assignment_mailbox_item
    {
      "item_type" => "execution_assignment",
      "item_id" => "mailbox-item-1",
      "protocol_message_id" => "protocol-message-1",
      "logical_work_id" => "logical-work-1",
      "attempt_no" => 1,
      "control_plane" => "agent",
      "payload" => {
        "task" => {
          "agent_task_run_id" => "task-1",
          "workflow_run_id" => "workflow-1",
          "workflow_node_id" => "node-1",
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
        },
      },
    }
  end

  def assert_eventually(timeout_seconds: 2)
    deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

    until yield
      raise "condition was not met before timeout" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at

      sleep(0.01)
    end
  end
end
