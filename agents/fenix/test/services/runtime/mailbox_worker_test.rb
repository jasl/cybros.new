require "test_helper"
require "active_job/test_helper"

class Runtime::MailboxWorkerTest < ActiveSupport::TestCase
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
    Shared::Values::MailboxDeliveryTracker.reset!
    @original_control_plane_client =
      if Shared::ControlPlane.instance_variable_defined?(:@client)
        Shared::ControlPlane.instance_variable_get(:@client)
      else
        :__undefined__
      end
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    Shared::Values::MailboxDeliveryTracker.reset!

    if @original_control_plane_client == :__undefined__
      Shared::ControlPlane.remove_instance_variable(:@client) if Shared::ControlPlane.instance_variable_defined?(:@client)
    else
      Shared::ControlPlane.client = @original_control_plane_client
    end
  end

  test "agent task close requests emit close lifecycle reports" do
    client = build_control_client

    result = Runtime::MailboxWorker.call(
      mailbox_item: close_request(resource_type: "AgentTaskRun", resource_id: "task-1"),
      deliver_reports: true,
      control_client: client
    )

    assert_equal :handled, result
    assert_equal %w[resource_close_acknowledged resource_closed], client.reported_payloads.map { |payload| payload.fetch("method_id") }
  end

  test "subagent connection close requests emit close lifecycle reports" do
    client = build_control_client

    result = Runtime::MailboxWorker.call(
      mailbox_item: close_request(resource_type: "SubagentConnection", resource_id: "subagent-1"),
      deliver_reports: true,
      control_client: client
    )

    assert_equal :handled, result
    assert_equal %w[resource_close_acknowledged resource_closed], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "SubagentConnection", client.reported_payloads.last.fetch("resource_type")
  end

  test "close requests without report delivery do not require a configured control plane" do
    result = Runtime::MailboxWorker.call(
      mailbox_item: close_request(resource_type: "AgentTaskRun", resource_id: "task-1"),
      deliver_reports: false
    )

    assert_equal :handled, result
  end

  test "non-inline executable mailbox items enqueue the runtime mailbox job" do
    Shared::ControlPlane.client = build_control_client
    mailbox_item = executable_mailbox_item

    result = nil

    assert_enqueued_with(job: MailboxExecutionJob) do
      result = Runtime::MailboxWorker.call(mailbox_item: mailbox_item, inline: false)
    end

    assert_equal "queued", result.status
    assert_equal mailbox_item.fetch("item_id"), result.mailbox_item_id
  end

  test "queued executable mailbox items are settled by the runtime mailbox job" do
    client = build_control_client
    Shared::ControlPlane.client = client
    mailbox_item = executable_mailbox_item

    assert_enqueued_with(job: MailboxExecutionJob) do
      Runtime::MailboxWorker.call(
        mailbox_item: mailbox_item,
        deliver_reports: true,
        inline: false
      )
    end

    perform_enqueued_jobs

    assert_equal ["agent_failed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal mailbox_item.fetch("item_id"), client.reported_payloads.last.fetch("mailbox_item_id")
  end

  test "non-inline executable mailbox items ignore duplicate deliveries for the same mailbox item" do
    Shared::ControlPlane.client = build_control_client
    mailbox_item = executable_mailbox_item

    assert_enqueued_jobs 1 do
      Runtime::MailboxWorker.call(mailbox_item: mailbox_item, inline: false)
      Runtime::MailboxWorker.call(mailbox_item: mailbox_item.deep_dup, inline: false)
    end
  end

  test "non-inline executable mailbox items allow redelivery when delivery number increases" do
    Shared::ControlPlane.client = build_control_client
    mailbox_item = executable_mailbox_item

    assert_enqueued_jobs 2 do
      Runtime::MailboxWorker.call(mailbox_item: mailbox_item, inline: false)
      Runtime::MailboxWorker.call(
        mailbox_item: mailbox_item.deep_dup.merge("delivery_no" => 2),
        inline: false
      )
    end
  end

  test "queued executable mailbox items serialize control plane context for out-of-process execution" do
    client = Shared::ControlPlane::Client.new(
      base_url: "https://core-matrix.example.test",
      agent_connection_credential: "agent-secret"
    )
    mailbox_item = executable_mailbox_item

    assert_enqueued_with(job: MailboxExecutionJob) do
      Runtime::MailboxWorker.call(
        mailbox_item: mailbox_item,
        deliver_reports: true,
        control_client: client,
        inline: false
      )
    end

    serialized_context = enqueued_jobs.last.fetch(:args).second.fetch("control_plane_context")

    assert_equal "https://core-matrix.example.test", serialized_context.fetch("base_url")
    assert_equal "agent-secret", serialized_context.fetch("agent_connection_credential")
  end

  test "inline executable mailbox items emit terminal failure reports" do
    client = build_control_client
    mailbox_item = executable_mailbox_item

    result = Runtime::MailboxWorker.call(
      mailbox_item: mailbox_item,
      deliver_reports: true,
      control_client: client,
      inline: true
    )

    assert_equal "failed", result.fetch("status")
    assert_equal ["agent_failed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "tool_not_allowed", client.reported_payloads.last.dig("error_payload", "code")
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

  def executable_mailbox_item
    {
      "item_type" => "agent_request",
      "item_id" => "mailbox-item-1",
      "protocol_message_id" => "protocol-message-1",
      "logical_work_id" => "logical-work-1",
      "attempt_no" => 1,
      "control_plane" => "agent",
      "payload" => {
        "request_kind" => "execute_tool",
        "task" => {
          "agent_task_run_id" => "task-1",
          "workflow_run_id" => "workflow-1",
          "workflow_node_id" => "node-1",
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
        },
        "agent_context" => {
          "allowed_tool_names" => [],
        },
        "tool_call" => {
          "call_id" => "tool-call-1",
          "tool_name" => "exec_command",
          "arguments" => {
            "command_line" => "pwd",
          },
        },
      },
    }
  end
end
