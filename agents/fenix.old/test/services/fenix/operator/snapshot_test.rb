require "test_helper"
require "open3"

class Fenix::Operator::SnapshotTest < ActiveSupport::TestCase
  FakeBrowserHost = Struct.new(:commands, :closed, keyword_init: true) do
    def dispatch(command:, arguments:)
      commands << { "command" => command, "arguments" => arguments }

      case command
      when "open"
        { "current_url" => arguments["url"] }
      when "navigate"
        { "current_url" => arguments["url"] }
      when "close"
        self.closed = true
        { "closed" => true }
      else
        {}
      end
    end

    def close
      self.closed = true
    end
  end

  test "writes operator_state.json with current task resource summaries under the conversation context tree" do
    Dir.mktmpdir do |tmpdir|
      root = Pathname.new(tmpdir)
      layout = Fenix::Workspace::Bootstrap.call(workspace_root: root, conversation_id: "conversation_123")
      root.join("notes").mkpath
      root.join("notes/todo.md").write("todo\n")

      stdin, stdout, stderr, wait_thread = Open3.popen3("/bin/sh", "-lc", "sleep 30")
      Fenix::Runtime::CommandRunRegistry.register(
        command_run_id: "command-run-1",
        agent_task_run_id: "task-1",
        stdin: stdin,
        stdout: stdout,
        stderr: stderr,
        wait_thread: wait_thread
      )
      Fenix::Runtime::CommandRunRegistry.append_output(
        command_run_id: "command-run-1",
        stream: "stdout",
        text: "hello\n"
      )

      proc_stdin, proc_stdout, proc_stderr, proc_wait_thread = Open3.popen3("/bin/sh", "-lc", "sleep 30")
      Fenix::Processes::Manager.register(
        process_run_id: "process-run-1",
        agent_task_run_id: "task-1",
        stdin: proc_stdin,
        stdout: proc_stdout,
        stderr: proc_stderr,
        wait_thread: proc_wait_thread,
        start_monitoring: false
      )
      Fenix::Processes::Manager.append_output(
        process_run_id: "process-run-1",
        stream: "stdout",
        text: "process\n"
      )
      Fenix::Processes::ProxyRegistry.register(process_run_id: "process-run-1", target_port: 4200)

      other_cmd_stdin, other_cmd_stdout, other_cmd_stderr, other_cmd_wait_thread = Open3.popen3("/bin/sh", "-lc", "sleep 30")
      Fenix::Runtime::CommandRunRegistry.register(
        command_run_id: "command-run-2",
        agent_task_run_id: "task-2",
        stdin: other_cmd_stdin,
        stdout: other_cmd_stdout,
        stderr: other_cmd_stderr,
        wait_thread: other_cmd_wait_thread
      )
      other_proc_stdin, other_proc_stdout, other_proc_stderr, other_proc_wait_thread = Open3.popen3("/bin/sh", "-lc", "sleep 30")
      Fenix::Processes::Manager.register(
        process_run_id: "process-run-2",
        agent_task_run_id: "task-2",
        stdin: other_proc_stdin,
        stdout: other_proc_stdout,
        stderr: other_proc_stderr,
        wait_thread: other_proc_wait_thread,
        start_monitoring: false
      )

      host_factory = ->(session_id:) { FakeBrowserHost.new(commands: [], closed: false) }
      Fenix::Browser::SessionManager.call(action: "open", url: "https://example.com", host_factory:, agent_task_run_id: "task-1")
      Fenix::Browser::SessionManager.call(action: "open", url: "https://example.org", host_factory:, agent_task_run_id: "task-2")

      snapshot = Fenix::Operator::Snapshot.call(
        workspace_root: root,
        conversation_id: "conversation_123",
        agent_task_run_id: "task-1"
      )
      persisted = JSON.parse(layout.conversation_operator_state_file.read)

      assert_equal snapshot, persisted
      assert_equal ".fenix/conversations/conversation_123/context/summary.md", snapshot.dig("memory", "conversation_summary_path")
      assert snapshot.fetch("workspace").fetch("highlights").any? { |entry| entry.fetch("path") == "notes" }
      assert_equal ["command-run-1"], snapshot.fetch("command_runs").map { |entry| entry.fetch("command_run_id") }
      assert_equal ["process-run-1"], snapshot.fetch("process_runs").map { |entry| entry.fetch("process_run_id") }
      assert_equal "/dev/process-run-1", snapshot.fetch("process_runs").fetch(0).fetch("proxy_path")
      assert_equal ["https://example.com"], snapshot.fetch("browser_sessions").map { |entry| entry.fetch("current_url") }
    ensure
      Fenix::Browser::SessionManager.reset!
      Fenix::Processes::Manager.reset!
      Fenix::Processes::ProxyRegistry.reset!
      Fenix::Runtime::CommandRunRegistry.reset!
    end
  end
end
