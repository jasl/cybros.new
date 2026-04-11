require "test_helper"
require "active_job/test_helper"

class Fenix::Runtime::MailboxWorkerPerfTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
    Fenix::Shared::Values::MailboxDeliveryTracker.reset!
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    Fenix::Shared::Values::MailboxDeliveryTracker.reset!
  end

  test "publishes mailbox execution perf event for inline execution" do
    events = []
    original_execute = Fenix::Runtime::ExecuteMailboxItem.method(:call)

    Fenix::Runtime::ExecuteMailboxItem.singleton_class.define_method(:call) do |**kwargs|
      {
        "status" => "ok",
        "mailbox_item_id" => kwargs.fetch(:mailbox_item).fetch("item_id"),
      }
    end

    ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.runtime.mailbox_execution") do
      Fenix::Runtime::MailboxWorker.call(
        mailbox_item: execution_assignment_mailbox_item,
        deliver_reports: false,
        inline: true
      )
    end

    assert_equal 1, events.length
    assert_equal true, events.first.fetch("success")
    assert_equal "mailbox-item-1", events.first.fetch("mailbox_item_public_id")
    assert_equal "agent", events.first.fetch("control_plane")
    assert_equal "conversation-1", events.first.fetch("conversation_public_id")
    assert_equal "turn-1", events.first.fetch("turn_public_id")
    assert_equal "agent-1", events.first.fetch("agent_public_id")
    assert_equal "user-1", events.first.fetch("user_public_id")
  ensure
    Fenix::Runtime::ExecuteMailboxItem.singleton_class.define_method(:call, original_execute)
  end

  test "publishes mailbox execution error metadata when inline execution raises" do
    events = []
    original_execute = Fenix::Runtime::ExecuteMailboxItem.method(:call)

    Fenix::Runtime::ExecuteMailboxItem.singleton_class.define_method(:call) do |**_kwargs|
      raise "boom"
    end

    error = assert_raises(RuntimeError) do
      ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.runtime.mailbox_execution") do
        Fenix::Runtime::MailboxWorker.call(
          mailbox_item: execution_assignment_mailbox_item,
          deliver_reports: false,
          inline: true
        )
      end
    end

    assert_equal "boom", error.message
    assert_equal 1, events.length
    assert_equal false, events.first.fetch("success")
    assert_equal "RuntimeError", events.first.dig("metadata", "error_class")
    assert_equal "boom", events.first.dig("metadata", "message")
  ensure
    Fenix::Runtime::ExecuteMailboxItem.singleton_class.define_method(:call, original_execute)
  end

  test "enqueues mailbox execution job with queue timing metadata" do
    assert_enqueued_with(
      job: Fenix::Runtime::MailboxExecutionJob,
      queue: "runtime_control",
      args: ->(job_args) do
        job_args.first.fetch("item_id") == "mailbox-item-1" &&
          job_args.second.is_a?(Hash) &&
          job_args.second[:queue_name] == "runtime_control" &&
          Time.iso8601(job_args.second.fetch(:enqueued_at_iso8601)).is_a?(Time)
      rescue ArgumentError, KeyError
        false
      end
    ) do
      Fenix::Runtime::MailboxWorker.call(
        mailbox_item: execution_assignment_mailbox_item,
        deliver_reports: false,
        inline: false
      )
    end
  end

  private

  def execution_assignment_mailbox_item
    {
      "item_type" => "execution_assignment",
      "item_id" => "mailbox-item-1",
      "protocol_message_id" => "protocol-message-1",
      "logical_work_id" => "logical-work-1",
      "attempt_no" => 1,
      "control_plane" => "agent",
      "payload" => {
        "runtime_context" => {
          "agent_id" => "agent-1",
          "user_id" => "user-1",
        },
        "task" => {
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "workflow_node_id" => "node-1",
        },
      },
    }
  end
end
