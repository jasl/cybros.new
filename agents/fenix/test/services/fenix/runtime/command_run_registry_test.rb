require "test_helper"
require "open3"

class Fenix::Runtime::CommandRunRegistryTest < ActiveSupport::TestCase
  test "list and output snapshot expose local attached command projections" do
    stdin = nil
    stdout = nil
    stderr = nil
    wait_thread = nil
    command_run_id = "command-run-#{SecureRandom.uuid}"

    begin
      stdin, stdout, stderr, wait_thread = Open3.popen3("/bin/sh", "-lc", "cat")

      Fenix::Runtime::CommandRunRegistry.register(
        command_run_id: command_run_id,
        runtime_owner_id: "task-1",
        stdin: stdin,
        stdout: stdout,
        stderr: stderr,
        wait_thread: wait_thread
      )
      Fenix::Runtime::CommandRunRegistry.append_output(
        command_run_id: command_run_id,
        stream: "stdout",
        text: "hello from stdout\n"
      )
      Fenix::Runtime::CommandRunRegistry.append_output(
        command_run_id: command_run_id,
        stream: "stderr",
        text: "hello from stderr\n"
      )

      entries = Fenix::Runtime::CommandRunRegistry.list(runtime_owner_id: "task-1")
      snapshot = Fenix::Runtime::CommandRunRegistry.output_snapshot(command_run_id: command_run_id)

      assert_equal 1, entries.length
      assert_equal command_run_id, entries.first.fetch("command_run_id")
      assert_equal "task-1", entries.first.fetch("runtime_owner_id")
      assert_equal "running", entries.first.fetch("lifecycle_state")
      assert_equal "hello from stdout\n".bytesize, entries.first.fetch("stdout_bytes")
      assert_equal "hello from stderr\n".bytesize, entries.first.fetch("stderr_bytes")
      assert_equal "hello from stdout\n", snapshot.fetch("stdout_tail")
      assert_equal "hello from stderr\n", snapshot.fetch("stderr_tail")
    ensure
      Fenix::Runtime::CommandRunRegistry.reset! if defined?(Fenix::Runtime::CommandRunRegistry)
      stdin&.close unless stdin.nil? || stdin.closed?
      stdout&.close unless stdout.nil? || stdout.closed?
      stderr&.close unless stderr.nil? || stderr.closed?
      Process.kill("KILL", wait_thread.pid) if wait_thread&.alive?
    end
  end
end
