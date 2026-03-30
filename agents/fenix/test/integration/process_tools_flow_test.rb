require "test_helper"

class ProcessToolsFlowTest < ActiveSupport::TestCase
  test "process_exec routes through the process launcher and carries proxy metadata into ProcessRun creation" do
    control_client = build_runtime_control_client
    routed_call = nil
    original_call = Fenix::Processes::Launcher.method(:call)

    Fenix::Processes::Launcher.define_singleton_method(:call) do |**kwargs|
      routed_call = kwargs
      {
        "process_run_id" => kwargs.fetch(:process_run).fetch("process_run_id"),
        "lifecycle_state" => "running",
        "proxy_path" => "/dev/#{kwargs.fetch(:process_run).fetch("process_run_id")}",
        "proxy_target_url" => "http://127.0.0.1:#{kwargs.fetch(:proxy_port)}",
      }
    end

    begin
      result = Fenix::Runtime::ExecuteAssignment.call(
        mailbox_item: runtime_assignment_payload(
          mode: "deterministic_tool",
          task_payload: {
            "tool_name" => "process_exec",
            "command_line" => "bin/dev",
            "proxy_port" => 4100,
          },
          agent_context: default_agent_context.merge(
            "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["process_exec"]
          )
        ),
        control_client: control_client
      )

      assert_equal "completed", result.status
      assert_match(/\/dev\/process-run-/, result.output)
      assert_equal 4100, routed_call.fetch(:proxy_port)
      assert_equal 4100, control_client.process_run_requests.first.dig("metadata", "proxy", "target_port")
    ensure
      Fenix::Processes::Launcher.define_singleton_method(:call, original_call)
    end
  end

  test "process operator helpers inspect active process handles and proxy metadata" do
    stdin = nil
    stdout = nil
    stderr = nil
    wait_thread = nil
    process_run_id = "process-run-#{SecureRandom.uuid}"
    begin
      stdin, stdout, stderr, wait_thread = Open3.popen3("/bin/sh", "-lc", "sleep 30")

      Fenix::Processes::Manager.register(
        process_run_id: process_run_id,
        stdin: stdin,
        stdout: stdout,
        stderr: stderr,
        wait_thread: wait_thread,
        start_monitoring: false
      )
      Fenix::Processes::Manager.append_output(
        process_run_id: process_run_id,
        stream: "stdout",
        text: "process output\n"
      )
      Fenix::Processes::ProxyRegistry.register(process_run_id: process_run_id, target_port: 4200)

      allowed_tool_names = default_agent_context.fetch("allowed_tool_names") + %w[process_list process_read_output process_proxy_info]

      listed = Fenix::Runtime::ExecuteAssignment.call(
        mailbox_item: runtime_assignment_payload(
          mode: "deterministic_tool",
          task_payload: { "tool_name" => "process_list" },
          agent_context: default_agent_context.merge("allowed_tool_names" => allowed_tool_names)
        )
      )
      listed_invocation = listed.reports.last.fetch("terminal_payload").fetch("tool_invocations").fetch(0)
      assert listed_invocation.dig("response_payload", "entries").any? { |entry| entry.fetch("process_run_id") == process_run_id }

      output = Fenix::Runtime::ExecuteAssignment.call(
        mailbox_item: runtime_assignment_payload(
          mode: "deterministic_tool",
          task_payload: {
            "tool_name" => "process_read_output",
            "process_run_id" => process_run_id,
          },
          agent_context: default_agent_context.merge("allowed_tool_names" => allowed_tool_names)
        )
      )
      output_invocation = output.reports.last.fetch("terminal_payload").fetch("tool_invocations").fetch(0)
      assert_equal "process output\n", output_invocation.dig("response_payload", "stdout_tail")

      proxy_info = Fenix::Runtime::ExecuteAssignment.call(
        mailbox_item: runtime_assignment_payload(
          mode: "deterministic_tool",
          task_payload: {
            "tool_name" => "process_proxy_info",
            "process_run_id" => process_run_id,
          },
          agent_context: default_agent_context.merge("allowed_tool_names" => allowed_tool_names)
        )
      )
      proxy_invocation = proxy_info.reports.last.fetch("terminal_payload").fetch("tool_invocations").fetch(0)
      assert_equal "/dev/#{process_run_id}", proxy_invocation.dig("response_payload", "proxy_path")
      assert_equal "http://127.0.0.1:4200", proxy_invocation.dig("response_payload", "proxy_target_url")
    ensure
      Fenix::Processes::Manager.reset!
      Fenix::Processes::ProxyRegistry.reset!
      stdin&.close unless stdin.nil? || stdin.closed?
      stdout&.close unless stdout.nil? || stdout.closed?
      stderr&.close unless stderr.nil? || stderr.closed?
      Process.kill("KILL", wait_thread.pid) if wait_thread&.alive?
    end
  end
end
