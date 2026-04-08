require "test_helper"
require "open3"

class Fenix::Runtime::MailboxWorkerTest < ActiveSupport::TestCase
  test "execution assignments create one durable runtime attempt and enqueue it once" do
    mailbox_item = runtime_assignment_payload(mode: "deterministic_tool").merge(
      "item_type" => "execution_assignment"
    )

    runtime_execution = nil

    assert_enqueued_with(job: RuntimeExecutionJob, queue: "runtime_pure_tools") do
      runtime_execution = Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
    end

    assert_instance_of RuntimeExecution, runtime_execution
    assert_equal "queued", runtime_execution.status
    assert_equal mailbox_item.fetch("item_id"), runtime_execution.mailbox_item_id
    assert_equal mailbox_item.fetch("protocol_message_id"), runtime_execution.protocol_message_id
    assert_equal mailbox_item.fetch("logical_work_id"), runtime_execution.logical_work_id
    assert_equal mailbox_item.fetch("attempt_no"), runtime_execution.attempt_no
    assert_equal mailbox_item.fetch("control_plane"), runtime_execution.control_plane
    assert_equal "execution_assignment", runtime_execution.item_type
    assert_equal "execution_assignment", runtime_execution.request_kind
    assert_equal mailbox_item.fetch("payload"), runtime_execution.request_payload
    assert_equal mailbox_item, runtime_execution.to_mailbox_item

    assert_enqueued_jobs 0 do
      duplicate = Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
      assert_equal runtime_execution.id, duplicate.id
    end
  end

  test "registry-backed execution assignments route to the runtime_process_tools queue" do
    mailbox_item = runtime_assignment_payload(
      mode: "deterministic_tool",
      task_payload: { "tool_name" => "exec_command", "command_line" => "printf 'hello\\n'" },
      agent_context: default_agent_context.merge(
        "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[exec_command write_stdin]
      )
    ).merge("item_type" => "execution_assignment")

    assert_enqueued_with(job: RuntimeExecutionJob, queue: "runtime_process_tools") do
      Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
    end
  end

  test "prepare_round program requests route to the runtime_prepare_round queue" do
    mailbox_item = {
      "item_type" => "agent_program_request",
      "item_id" => "mailbox-item-#{SecureRandom.uuid}",
      "protocol_message_id" => "protocol-message-#{SecureRandom.uuid}",
      "logical_work_id" => "logical-work-#{SecureRandom.uuid}",
      "attempt_no" => 1,
      "control_plane" => "program",
      "payload" => shared_contract_fixture("core_matrix_fenix_prepare_round_mailbox_item").fetch("payload"),
    }

    assert_enqueued_with(job: RuntimeExecutionJob, queue: "runtime_prepare_round") do
      Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
    end
  end

  test "retries transient runtime execution creation failures before enqueueing" do
    mailbox_item = {
      "item_type" => "agent_program_request",
      "item_id" => "mailbox-item-#{SecureRandom.uuid}",
      "protocol_message_id" => "protocol-message-#{SecureRandom.uuid}",
      "logical_work_id" => "logical-work-#{SecureRandom.uuid}",
      "attempt_no" => 1,
      "control_plane" => "program",
      "payload" => shared_contract_fixture("core_matrix_fenix_prepare_round_mailbox_item").fetch("payload"),
    }

    original_create = RuntimeExecution.method(:create!)
    create_calls = 0

    singleton = RuntimeExecution.singleton_class
    singleton.send(:define_method, :create!) do |**attrs|
      create_calls += 1

      if create_calls == 1
        raise ActiveRecord::StatementInvalid.new("SQLite3::LockedException: database table is locked")
      end

      original_create.call(**attrs)
    end

    begin
      runtime_execution = nil

      assert_enqueued_with(job: RuntimeExecutionJob, queue: "runtime_prepare_round") do
        runtime_execution = Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
      end

      assert_equal 2, create_calls
      assert_instance_of RuntimeExecution, runtime_execution
      assert_equal mailbox_item.fetch("item_id"), runtime_execution.mailbox_item_id
      assert runtime_execution.reload.enqueued_at.present?
    ensure
      singleton.send(:define_method, :create!, original_create)
    end
  end

  test "retries transient runtime execution dispatch failures before marking the execution enqueued" do
    mailbox_item = {
      "item_type" => "agent_program_request",
      "item_id" => "mailbox-item-#{SecureRandom.uuid}",
      "protocol_message_id" => "protocol-message-#{SecureRandom.uuid}",
      "logical_work_id" => "logical-work-#{SecureRandom.uuid}",
      "attempt_no" => 1,
      "control_plane" => "program",
      "payload" => shared_contract_fixture("core_matrix_fenix_prepare_round_mailbox_item").fetch("payload"),
    }

    original_set = RuntimeExecutionJob.method(:set)
    set_calls = 0

    singleton = RuntimeExecutionJob.singleton_class
    singleton.send(:define_method, :set) do |**kwargs|
      set_calls += 1

      if set_calls == 1
        Class.new do
          def perform_later(*)
            raise ActiveRecord::StatementInvalid.new("SQLite3::LockedException: database table is locked")
          end
        end.new
      else
        original_set.call(**kwargs)
      end
    end

    begin
      runtime_execution = nil

      assert_enqueued_with(job: RuntimeExecutionJob, queue: "runtime_prepare_round") do
        runtime_execution = Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
      end

      assert_equal 2, set_calls
      assert runtime_execution.reload.enqueued_at.present?
    ensure
      singleton.send(:define_method, :set, original_set)
    end
  end

  test "re-dispatches queued runtime executions that were created before enqueue succeeded" do
    mailbox_item = {
      "item_type" => "agent_program_request",
      "item_id" => "mailbox-item-#{SecureRandom.uuid}",
      "protocol_message_id" => "protocol-message-#{SecureRandom.uuid}",
      "logical_work_id" => "logical-work-#{SecureRandom.uuid}",
      "attempt_no" => 1,
      "control_plane" => "program",
      "payload" => shared_contract_fixture("core_matrix_fenix_prepare_round_mailbox_item").fetch("payload"),
    }

    runtime_execution = RuntimeExecution.create!(runtime_execution_attributes(mailbox_item:))

    assert_nil runtime_execution.enqueued_at

    assert_enqueued_with(job: RuntimeExecutionJob, queue: "runtime_prepare_round") do
      duplicate = Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
      assert_equal runtime_execution.id, duplicate.id
    end

    assert runtime_execution.reload.enqueued_at.present?
  end

  test "registry-backed execute_program_tool requests route to the runtime_process_tools queue" do
    mailbox_item = shared_contract_fixture("core_matrix_fenix_execute_program_tool_mailbox_item").deep_dup
    mailbox_item["item_id"] = "mailbox-item-#{SecureRandom.uuid}"
    mailbox_item["protocol_message_id"] = "protocol-message-#{SecureRandom.uuid}"
    mailbox_item["logical_work_id"] = "logical-work-#{SecureRandom.uuid}"
    mailbox_item["payload"]["program_tool_call"] = {
      "call_id" => "tool-call-#{SecureRandom.uuid}",
      "tool_name" => "exec_command",
      "arguments" => {
        "command_line" => "printf 'hello\\n'",
        "timeout_seconds" => 5,
        "pty" => false,
      },
    }
    mailbox_item["payload"]["agent_context"]["allowed_tool_names"] = ["exec_command"]

    assert_enqueued_with(job: RuntimeExecutionJob, queue: "runtime_process_tools") do
      Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
    end
  end

  test "registry-backed follow-up execution assignments route to the runtime_process_tools queue" do
    {
      "command_run_list" => {},
      "command_run_read_output" => { "command_run_id" => "command-run-#{SecureRandom.uuid}" },
      "command_run_wait" => { "command_run_id" => "command-run-#{SecureRandom.uuid}" },
      "command_run_terminate" => { "command_run_id" => "command-run-#{SecureRandom.uuid}" },
      "browser_list" => {},
      "browser_session_info" => { "browser_session_id" => "browser-session-#{SecureRandom.uuid}" },
      "process_list" => {},
      "process_read_output" => { "process_run_id" => "process-run-#{SecureRandom.uuid}" },
      "process_proxy_info" => { "process_run_id" => "process-run-#{SecureRandom.uuid}" },
    }.each do |tool_name, arguments|
      mailbox_item = runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => tool_name,
          "arguments" => arguments,
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + [tool_name]
        )
      ).merge("item_type" => "execution_assignment")

      assert_enqueued_with(job: RuntimeExecutionJob, queue: "runtime_process_tools") do
        Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
      end
    end
  end

  test "registry-backed follow-up execute_program_tool requests route to the runtime_process_tools queue" do
    {
      "command_run_list" => {},
      "command_run_read_output" => { "command_run_id" => "command-run-#{SecureRandom.uuid}" },
      "command_run_wait" => { "command_run_id" => "command-run-#{SecureRandom.uuid}" },
      "command_run_terminate" => { "command_run_id" => "command-run-#{SecureRandom.uuid}" },
      "browser_list" => {},
      "browser_session_info" => { "browser_session_id" => "browser-session-#{SecureRandom.uuid}" },
      "process_list" => {},
      "process_read_output" => { "process_run_id" => "process-run-#{SecureRandom.uuid}" },
      "process_proxy_info" => { "process_run_id" => "process-run-#{SecureRandom.uuid}" },
    }.each do |tool_name, arguments|
      mailbox_item = shared_contract_fixture("core_matrix_fenix_execute_program_tool_mailbox_item").deep_dup
      mailbox_item["item_id"] = "mailbox-item-#{SecureRandom.uuid}"
      mailbox_item["protocol_message_id"] = "protocol-message-#{SecureRandom.uuid}"
      mailbox_item["logical_work_id"] = "logical-work-#{SecureRandom.uuid}"
      mailbox_item["payload"]["program_tool_call"] = {
        "call_id" => "tool-call-#{SecureRandom.uuid}",
        "tool_name" => tool_name,
        "arguments" => arguments,
      }
      mailbox_item["payload"]["agent_context"]["allowed_tool_names"] = [tool_name]

      assert_enqueued_with(job: RuntimeExecutionJob, queue: "runtime_process_tools") do
        Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
      end
    end
  end

  test "agent task close requests cancel queued runtime executions before they start" do
    agent_task_run_id = "task-#{SecureRandom.uuid}"
    mailbox_item = runtime_assignment_payload(mode: "deterministic_tool").merge(
      "item_type" => "execution_assignment"
    )
    mailbox_item.fetch("payload").fetch("task")["agent_task_run_id"] = agent_task_run_id

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
    payload.fetch("payload").fetch("task")["agent_task_run_id"] = agent_task_run_id

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

  test "subagent session close requests report a close lifecycle" do
    control_client = build_runtime_control_client
    mailbox_item = {
      "item_type" => "resource_close_request",
      "item_id" => "close-item-#{SecureRandom.uuid}",
      "payload" => {
        "resource_type" => "SubagentSession",
        "resource_id" => "subagent-session-#{SecureRandom.uuid}",
        "request_kind" => "subagent_close",
        "reason_kind" => "subagent_close_requested",
        "strictness" => "graceful",
      },
    }

    result = nil

    assert_enqueued_jobs 0 do
      result = Fenix::Runtime::MailboxWorker.call(
        mailbox_item: mailbox_item,
        deliver_reports: true,
        control_client: control_client
      )
    end

    assert_equal :handled, result

    method_ids = control_client.reported_payloads.map { |payload| payload.fetch("method_id") }

    assert_equal %w[resource_close_acknowledged resource_closed], method_ids
    terminal = control_client.reported_payloads.last
    assert_equal "SubagentSession", terminal.fetch("resource_type")
    assert_equal mailbox_item.dig("payload", "resource_id"), terminal.fetch("resource_id")
    assert_equal "graceful", terminal.fetch("close_outcome_kind")
    assert_equal({ "source" => "fenix_runtime" }, terminal.fetch("close_outcome_payload"))
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
