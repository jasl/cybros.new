require "test_helper"
require "open3"

class Fenix::Processes::ManagerTest < ActiveSupport::TestCase
  FakeControlClient = Struct.new(:payloads, keyword_init: true) do
    def report!(payload:)
      payloads << payload.deep_stringify_keys
      { "result" => "accepted" }
    end
  end

  test "registered processes stream output and settle graceful close through close reports" do
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

      Fenix::Processes::Manager.register(
        process_run_id: "process-#{SecureRandom.uuid}",
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

      result = Fenix::Processes::Manager.close!(
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
        control_client.payloads.any? { |payload| payload["method_id"] == "resource_closed" }
      end

      method_ids = control_client.payloads.map { |payload| payload.fetch("method_id") }
      assert_includes method_ids, "process_output"
      assert_includes method_ids, "resource_close_acknowledged"
      assert_includes method_ids, "resource_closed"

      terminal = control_client.payloads.reverse.find { |payload| payload["method_id"] == "resource_closed" }
      assert_equal "graceful", terminal.fetch("close_outcome_kind")
      assert_equal "ProcessRun", terminal.fetch("resource_type")
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

  test "missing process handles settle as residual abandonment" do
    control_client = FakeControlClient.new(payloads: [])

    result = Fenix::Processes::Manager.close!(
      mailbox_item: {
        "item_id" => "close-item-#{SecureRandom.uuid}",
        "payload" => {
          "resource_type" => "ProcessRun",
          "resource_id" => "process-#{SecureRandom.uuid}",
          "strictness" => "forced",
        },
      },
      deliver_reports: true,
      control_client: control_client
    )

    assert_equal :handled, result
    assert_equal ["resource_close_failed"], control_client.payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "residual_abandoned", control_client.payloads.first.fetch("close_outcome_kind")
  end

  test "spawn! reports process_started and process_exited for a naturally exiting background process" do
    control_client = FakeControlClient.new(payloads: [])
    process_run_id = "process-#{SecureRandom.uuid}"

    Fenix::Processes::Manager.spawn!(
      process_run_id: process_run_id,
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

    started = control_client.payloads.find { |payload| payload["method_id"] == "process_started" }
    terminal = control_client.payloads.reverse.find { |payload| payload["method_id"] == "process_exited" }

    assert_equal process_run_id, started.fetch("resource_id")
    assert_equal process_run_id, terminal.fetch("resource_id")
    assert_equal "stopped", terminal.fetch("lifecycle_state")
    assert_equal 0, terminal.fetch("exit_status")
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
