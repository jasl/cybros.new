require "test_helper"
require "open3"

class Fenix::Runtime::MailboxWorkerTest < ActiveSupport::TestCase
  test "execution assignments create one durable runtime attempt and enqueue it once" do
    mailbox_item = runtime_assignment_payload(mode: "deterministic_tool").merge(
      "item_type" => "execution_assignment"
    )

    runtime_execution = nil

    assert_enqueued_jobs 1 do
      runtime_execution = Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
    end

    assert_instance_of RuntimeExecution, runtime_execution
    assert_equal "queued", runtime_execution.status
    assert_equal mailbox_item.fetch("item_id"), runtime_execution.mailbox_item_id
    assert_equal mailbox_item.fetch("protocol_message_id"), runtime_execution.protocol_message_id
    assert_equal mailbox_item.fetch("logical_work_id"), runtime_execution.logical_work_id
    assert_equal mailbox_item.fetch("attempt_no"), runtime_execution.attempt_no
    assert_equal mailbox_item.fetch("runtime_plane"), runtime_execution.runtime_plane
    assert_equal mailbox_item, runtime_execution.mailbox_item_payload

    assert_enqueued_jobs 0 do
      duplicate = Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
      assert_equal runtime_execution.id, duplicate.id
    end
  end

  test "agent task close requests cancel queued runtime executions before they start" do
    agent_task_run_id = "task-#{SecureRandom.uuid}"
    mailbox_item = runtime_assignment_payload(mode: "deterministic_tool").merge(
      "item_type" => "execution_assignment"
    )
    mailbox_item.fetch("payload")["agent_task_run_id"] = agent_task_run_id

    runtime_execution = nil
    execute_assignment_singleton = Fenix::Runtime::ExecuteAssignment.singleton_class
    original_execute_assignment = Fenix::Runtime::ExecuteAssignment.method(:call)
    calls = []

    execute_assignment_singleton.send(:define_method, :call) do |**kwargs|
      calls << kwargs
      Fenix::Runtime::ExecuteAssignment::Result.new(
        status: "completed",
        reports: [],
        trace: [],
        output: "done"
      )
    end

    assert_enqueued_jobs 1 do
      runtime_execution = Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
    end

    Fenix::Runtime::MailboxWorker.call(
      mailbox_item: {
        "item_type" => "resource_close_request",
        "item_id" => "close-item-#{SecureRandom.uuid}",
        "payload" => {
          "resource_type" => "AgentTaskRun",
          "resource_id" => agent_task_run_id,
        },
      }
    )

    perform_enqueued_jobs

    assert_equal [], calls
    assert_equal "canceled", runtime_execution.reload.status
  ensure
    Fenix::Runtime::CommandRunRegistry.reset!
    execute_assignment_singleton.send(:define_method, :call, original_execute_assignment) if execute_assignment_singleton && original_execute_assignment
  end

  test "agent task close requests terminate command runs" do
    agent_task_run_id = "task-#{SecureRandom.uuid}"
    stdin = nil
    stdout = nil
    stderr = nil
    wait_thread = nil

    begin
      stdin, stdout, stderr, wait_thread = Open3.popen3("/bin/sh", "-lc", "cat")

      command_run = Fenix::Runtime::CommandRunRegistry.register(
        command_run_id: "command-run-#{SecureRandom.uuid}",
        agent_task_run_id: agent_task_run_id,
        stdin: stdin,
        stdout: stdout,
        stderr: stderr,
        wait_thread: wait_thread
      )

      result = nil

      assert_enqueued_jobs 0 do
        result = Fenix::Runtime::MailboxWorker.call(
          mailbox_item: {
            "item_type" => "resource_close_request",
            "payload" => {
              "resource_type" => "AgentTaskRun",
              "resource_id" => agent_task_run_id,
            },
          }
        )
      end

      assert_equal :handled, result
      assert_nil Fenix::Runtime::CommandRunRegistry.lookup(command_run_id: command_run.command_run_id)
      refute wait_thread.alive?
    ensure
      stdin&.close unless stdin.nil? || stdin.closed?
      stdout&.close unless stdout.nil? || stdout.closed?
      stderr&.close unless stderr.nil? || stderr.closed?
      Process.kill("KILL", wait_thread.pid) if wait_thread&.alive?
    end
  rescue Errno::ESRCH
    nil
  end

  test "agent task close requests terminate one-shot command runs that are still executing" do
    agent_task_run_id = "task-#{SecureRandom.uuid}"
    control_client = build_runtime_control_client
    payload = runtime_assignment_payload(
      mode: "deterministic_tool",
      task_payload: {
        "tool_name" => "exec_command",
        "command_line" => "sleep 30",
      },
      agent_context: default_agent_context.merge(
        "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["exec_command"]
      )
    )
    payload.fetch("payload")["agent_task_run_id"] = agent_task_run_id

    execution_thread = Thread.new do
      Fenix::Runtime::ExecuteAssignment.call(mailbox_item: payload, control_client: control_client)
    end

    command_run_id = nil
    assert_eventually do
      command_run_id = control_client.command_run_requests.first&.dig("response", "command_run_id")
      command_run_id.present? &&
        Fenix::Runtime::CommandRunRegistry.lookup(command_run_id: command_run_id).present?
    end

    Fenix::Runtime::MailboxWorker.call(
      mailbox_item: {
        "item_type" => "resource_close_request",
        "payload" => {
          "resource_type" => "AgentTaskRun",
          "resource_id" => agent_task_run_id,
        },
      }
    )

    execution_thread.join(2)

    refute execution_thread.alive?
    assert_nil Fenix::Runtime::CommandRunRegistry.lookup(command_run_id: command_run_id)
  ensure
    execution_thread&.kill if execution_thread&.alive?
  end

  test "process run close requests route into the process manager" do
    mailbox_item = {
      "item_type" => "resource_close_request",
      "item_id" => "close-item-#{SecureRandom.uuid}",
      "payload" => {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{SecureRandom.uuid}",
        "strictness" => "graceful",
      },
    }

    received_mailbox_item = nil
    result = nil
    test_case = self

    original_close = Fenix::Processes::Manager.method(:close!)

    Fenix::Processes::Manager.singleton_class.define_method(
      :close!,
      lambda do |mailbox_item:, deliver_reports:, control_client:|
        received_mailbox_item = mailbox_item
        test_case.assert_equal true, deliver_reports
        test_case.assert_equal :fake_control_client, control_client
        :handled
      end
    )

    begin
      assert_enqueued_jobs 0 do
        result = Fenix::Runtime::MailboxWorker.call(
          mailbox_item: mailbox_item,
          deliver_reports: true,
          control_client: :fake_control_client
        )
      end
    ensure
      Fenix::Processes::Manager.singleton_class.define_method(:close!, original_close)
    end

    assert_equal :handled, result
    assert_equal mailbox_item, received_mailbox_item
  end

  private

  def assert_eventually(timeout_seconds: 2, &block)
    deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

    until yield
      raise "condition was not met before timeout" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at

      sleep(0.01)
    end
  end
end
