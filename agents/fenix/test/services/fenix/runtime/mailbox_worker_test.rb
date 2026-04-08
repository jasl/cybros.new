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
    @original_control_plane_client =
      if Fenix::Runtime::ControlPlane.instance_variable_defined?(:@client)
        Fenix::Runtime::ControlPlane.instance_variable_get(:@client)
      else
        :__undefined__
      end
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs

    if @original_control_plane_client == :__undefined__
      Fenix::Runtime::ControlPlane.remove_instance_variable(:@client) if Fenix::Runtime::ControlPlane.instance_variable_defined?(:@client)
    else
      Fenix::Runtime::ControlPlane.client = @original_control_plane_client
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

  test "subagent session close requests emit close lifecycle reports" do
    client = build_control_client

    result = Fenix::Runtime::MailboxWorker.call(
      mailbox_item: close_request(resource_type: "SubagentSession", resource_id: "subagent-1"),
      deliver_reports: true,
      control_client: client
    )

    assert_equal :handled, result
    assert_equal %w[resource_close_acknowledged resource_closed], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "SubagentSession", client.reported_payloads.last.fetch("resource_type")
  end

  test "close requests without report delivery do not require a configured control plane" do
    result = Fenix::Runtime::MailboxWorker.call(
      mailbox_item: close_request(resource_type: "AgentTaskRun", resource_id: "task-1"),
      deliver_reports: false
    )

    assert_equal :handled, result
  end

  test "process run close requests report failure when no local process manager is available" do
    client = build_control_client

    result = Fenix::Runtime::MailboxWorker.call(
      mailbox_item: close_request(resource_type: "ProcessRun", resource_id: "process-1"),
      deliver_reports: true,
      control_client: client
    )

    assert_equal :unsupported, result
    assert_equal ["resource_close_failed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "ProcessRun", client.reported_payloads.last.fetch("resource_type")
  end

  test "non-inline executable mailbox items enqueue the runtime mailbox job" do
    Fenix::Runtime::ControlPlane.client = build_control_client
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
    Fenix::Runtime::ControlPlane.client = client
    mailbox_item = execution_assignment_mailbox_item

    assert_enqueued_with(job: Fenix::Runtime::MailboxExecutionJob) do
      Fenix::Runtime::MailboxWorker.call(
        mailbox_item: mailbox_item,
        deliver_reports: true,
        inline: false
      )
    end

    perform_enqueued_jobs

    assert_equal ["execution_fail"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal mailbox_item.fetch("item_id"), client.reported_payloads.last.fetch("mailbox_item_id")
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
    assert_equal ["execution_fail"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "executor_tool_slice_not_ready", client.reported_payloads.last.dig("terminal_payload", "code")
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
      "control_plane" => "executor",
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
      "control_plane" => "program",
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
end
