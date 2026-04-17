require "test_helper"
require "open3"

class NexusProcessesManagerTest < ActiveSupport::TestCase
  FakeControlClient = Struct.new(:payloads, keyword_init: true) do
    def report!(payload:)
      payloads << payload.deep_stringify_keys
      { "result" => "accepted" }
    end
  end

  teardown do
    Processes::Manager.reset!
    Processes::ProxyRegistry.reset!
  end

  test "spawn! reports process_started and process_exited for a naturally exiting detached process" do
    control_client = FakeControlClient.new(payloads: [])
    process_run_id = "process-#{SecureRandom.uuid}"

    Processes::Manager.spawn!(
      process_run_id: process_run_id,
      runtime_owner_id: "task-1",
      command_line: "printf 'hello from process\\n'",
      control_client: control_client
    )

    assert_eventually do
      control_client.payloads.any? { |payload| payload["method_id"] == "process_started" } &&
        control_client.payloads.any? { |payload| payload["method_id"] == "process_exited" }
    end

    method_ids = control_client.payloads.map { |payload| payload.fetch("method_id") }

    assert_includes method_ids, "process_started"
    assert_includes method_ids, "process_output"
    assert_includes method_ids, "process_exited"

    terminal = control_client.payloads.reverse.find { |payload| payload["method_id"] == "process_exited" }

    assert_equal process_run_id, terminal.fetch("resource_id")
    assert_equal "stopped", terminal.fetch("lifecycle_state")
    assert_equal 0, terminal.fetch("exit_status")
  end

  test "spawn! passes the provided environment into the child process" do
    control_client = FakeControlClient.new(payloads: [])
    process_run_id = "process-#{SecureRandom.uuid}"

    Processes::Manager.spawn!(
      process_run_id: process_run_id,
      runtime_owner_id: "task-1",
      command_line: "printf '%s\\n' \"$HELLO\"",
      control_client: control_client,
      environment: ENV.to_h.merge("HELLO" => "workspace")
    )

    assert_eventually do
      snapshot = Processes::Manager.output_snapshot(process_run_id: process_run_id)
      snapshot.present? && snapshot.fetch("stdout_tail").include?("workspace")
    end

    snapshot = Processes::Manager.output_snapshot(process_run_id: process_run_id)
    assert_includes snapshot.fetch("stdout_tail"), "workspace"
  end

  test "registered processes settle graceful close through close reports" do
    control_client = FakeControlClient.new(payloads: [])
    stdin = nil
    stdout = nil
    stderr = nil
    wait_thread = nil

    begin
      stdin, stdout, stderr, wait_thread = Open3.popen3(
        "/bin/sh",
        "-lc",
        "trap 'exit 0' TERM; printf 'hello from process\\n'; while :; do sleep 1; done"
      )

      Processes::Manager.register(
        process_run_id: "process-#{SecureRandom.uuid}",
        runtime_owner_id: "task-1",
        stdin: stdin,
        stdout: stdout,
        stderr: stderr,
        wait_thread: wait_thread,
        control_client: control_client
      )

      assert_eventually do
        control_client.payloads.any? { |payload| payload["method_id"] == "process_output" }
      end

      process_run_id = control_client.payloads.find { |payload| payload["method_id"] == "process_output" }.fetch("resource_id")

      result = Processes::Manager.close!(
        mailbox_item: {
          "item_id" => "close-item-#{SecureRandom.uuid}",
          "payload" => {
            "resource_type" => "ProcessRun",
            "resource_id" => process_run_id,
            "strictness" => "graceful",
          },
        },
        deliver_reports: true,
        control_client: control_client
      )

      assert_equal :handled, result

      assert_eventually do
        control_client.payloads.any? { |payload| payload["method_id"] == "resource_closed" && payload["resource_id"] == process_run_id }
      end

      terminal = control_client.payloads.reverse.find { |payload| payload["method_id"] == "resource_closed" }
      assert_equal "graceful", terminal.fetch("close_outcome_kind")
      assert_equal process_run_id, terminal.fetch("resource_id")
    ensure
      stdin&.close unless stdin.nil? || stdin.closed?
      stdout&.close unless stdout.nil? || stdout.closed?
      stderr&.close unless stderr.nil? || stderr.closed?
      Process.kill("KILL", wait_thread.pid) if wait_thread&.alive?
    end
  rescue Errno::ESRCH
    nil
  end

  test "graceful close terminal report matches the shared contract fixture" do
    control_client = FakeControlClient.new(payloads: [])
    stdin = nil
    stdout = nil
    stderr = nil
    wait_thread = nil

    begin
      stdin, stdout, stderr, wait_thread = Open3.popen3(
        "/bin/sh",
        "-lc",
        "trap 'exit 0' TERM; while :; do sleep 1; done"
      )

      Processes::Manager.register(
        process_run_id: "process-run-public-id",
        runtime_owner_id: "task-1",
        stdin: stdin,
        stdout: stdout,
        stderr: stderr,
        wait_thread: wait_thread,
        control_client: control_client
      )

      result = Processes::Manager.close!(
        mailbox_item: {
          "item_id" => "mailbox-item-close-public-id",
          "payload" => {
            "resource_type" => "ProcessRun",
            "resource_id" => "process-run-public-id",
            "strictness" => "graceful",
          },
        },
        deliver_reports: true,
        control_client: control_client
      )

      assert_equal :handled, result

      assert_eventually do
        control_client.payloads.any? { |payload| payload["method_id"] == "resource_closed" && payload["resource_id"] == "process-run-public-id" }
      end

      terminal = control_client.payloads.reverse.find { |payload| payload["method_id"] == "resource_closed" }
      assert_equal resource_closed_report_contract_fixture, normalize_resource_closed_report(terminal)
    ensure
      stdin&.close unless stdin.nil? || stdin.closed?
      stdout&.close unless stdout.nil? || stdout.closed?
      stderr&.close unless stderr.nil? || stderr.closed?
      Process.kill("KILL", wait_thread.pid) if wait_thread&.alive?
    end
  rescue Errno::ESRCH
    nil
  end

  private

  def resource_closed_report_contract_fixture
    JSON.parse(
      File.read(
        Rails.root.join("..", "..", "shared", "fixtures", "contracts", "nexus_resource_closed_report.json")
      )
    )
  end

  def normalize_resource_closed_report(report)
    normalized = report.deep_dup
    normalized.delete("protocol_message_id")
    normalized
  end

  def assert_eventually(timeout_seconds: 2)
    deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

    until yield
      raise "condition was not met before timeout" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at

      sleep(0.01)
    end
  end
end
