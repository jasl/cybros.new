require "test_helper"

class Fenix::Runtime::ExecuteAssignmentTest < ActiveSupport::TestCase
  test "execution topology marks runtime_process_tools as the registry-backed queue" do
    assert Fenix::Runtime::ExecutionTopology.registry_backed_queue?("runtime_process_tools")
    refute Fenix::Runtime::ExecutionTopology.registry_backed_queue?("runtime_pure_tools")
  end

  test "deterministic tool path emits start progress and complete reports through retained hooks" do
    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(mode: "deterministic_tool")
    )

    assert_equal %w[execution_started execution_progress execution_complete],
      result.reports.map { |report| report.fetch("method_id") }
    assert result.reports.all? { |report| report.key?("protocol_message_id") }
    assert result.reports.none? { |report| report.key?("message_id") }
    assert_equal "The calculator returned 4.", result.output
    assert_equal %w[prepare_turn compact_context review_tool_call project_tool_result finalize_output],
      result.trace.map { |entry| entry.fetch("hook") }
    assert_equal "completed", result.status

    started_invocation = result.reports.find { |report| report.fetch("method_id") == "execution_progress" }
      .dig("progress_payload", "tool_invocation")
    completed_invocation = result.reports.find { |report| report.fetch("method_id") == "execution_complete" }
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "started", started_invocation.fetch("event")
    assert_equal "calculator", started_invocation.fetch("tool_name")
    assert_equal "completed", completed_invocation.fetch("event")
    assert_equal "calculator", completed_invocation.fetch("tool_name")
    assert_equal started_invocation.fetch("call_id"), completed_invocation.fetch("call_id")
  end

  test "exec_command emits tool output progress and completes with structured command results" do
    control_client = build_runtime_control_client
    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "exec_command",
          "command_line" => "printf 'hello\\n'",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[exec_command write_stdin]
        )
      ),
      control_client: control_client
    )

    assert_equal "completed", result.status
    assert_equal %w[execution_started execution_progress execution_progress execution_complete],
      result.reports.map { |report| report.fetch("method_id") }

    started_invocation = result.reports.second.dig("progress_payload", "tool_invocation")
    output_progress = result.reports.third.fetch("progress_payload").fetch("tool_invocation_output")
    completed_invocation = result.reports.fourth
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "exec_command", started_invocation.fetch("tool_name")
    assert started_invocation.fetch("tool_invocation_id").present?
    assert started_invocation.fetch("command_run_id").present?
    assert_equal started_invocation.fetch("call_id"), output_progress.fetch("call_id")
    assert_equal started_invocation.fetch("tool_invocation_id"), output_progress.fetch("tool_invocation_id")
    assert_equal started_invocation.fetch("command_run_id"), output_progress.fetch("command_run_id")
    assert_equal "stdout", output_progress.fetch("output_chunks").fetch(0).fetch("stream")
    assert_equal "hello\n", output_progress.fetch("output_chunks").fetch(0).fetch("text")
    assert_equal "completed", completed_invocation.fetch("event")
    assert_equal "exec_command", completed_invocation.fetch("tool_name")
    assert_equal started_invocation.fetch("tool_invocation_id"), completed_invocation.fetch("tool_invocation_id")
    assert_equal started_invocation.fetch("command_run_id"), completed_invocation.fetch("command_run_id")
    assert_equal "Command exited with status 0 after streaming output.", result.output
    assert_equal started_invocation.fetch("command_run_id"), completed_invocation.dig("response_payload", "command_run_id")
    assert_equal 0, completed_invocation.dig("response_payload", "exit_status")
    assert_equal true, completed_invocation.dig("response_payload", "output_streamed")
    assert_equal 6, completed_invocation.dig("response_payload", "stdout_bytes")
    assert_equal 0, completed_invocation.dig("response_payload", "stderr_bytes")
    refute completed_invocation.fetch("response_payload").key?("stdout")
    refute completed_invocation.fetch("response_payload").key?("stderr")
    assert_equal ["exec_command"], control_client.tool_invocation_requests.map { |request| request.fetch("tool_name") }
    assert_equal [started_invocation.fetch("tool_invocation_id")], control_client.command_run_requests.map { |request| request.fetch("tool_invocation_id") }
  end

  test "exec_command routes through the exec command plugin runtime" do
    routed_call = nil
    control_client = build_runtime_control_client

    original_call = Fenix::Plugins::System::ExecCommand::Runtime.method(:call)
    Fenix::Plugins::System::ExecCommand::Runtime.define_singleton_method(:call) do |**kwargs|
      routed_call = kwargs
      {
        "command_run_id" => kwargs.fetch(:command_run).fetch("command_run_id"),
        "exit_status" => 0,
        "output_streamed" => false,
        "stdout_bytes" => 0,
        "stderr_bytes" => 0,
      }
    end

    begin
      result = Fenix::Runtime::ExecuteAssignment.call(
        mailbox_item: runtime_assignment_payload(
          mode: "deterministic_tool",
          task_payload: {
            "tool_name" => "exec_command",
            "command_line" => "printf 'hello\\n'",
          },
          agent_context: default_agent_context.merge(
            "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[exec_command write_stdin]
          )
        ),
        control_client: control_client
      )

      assert_equal "completed", result.status
    ensure
      Fenix::Plugins::System::ExecCommand::Runtime.define_singleton_method(:call, original_call)
    end

    assert_equal "exec_command", routed_call.fetch(:tool_call).fetch("tool_name")
    assert_equal "printf 'hello\\n'", routed_call.fetch(:tool_call).dig("arguments", "command_line")
    assert routed_call.fetch(:tool_invocation).fetch("tool_invocation_id").present?
    assert routed_call.fetch(:command_run).fetch("command_run_id").present?
  end

  test "exec_command can hand off an attached command run to write_stdin and finish with summary-only payloads" do
    agent_task_run_id = "task-#{SecureRandom.uuid}"
    control_client = build_runtime_control_client
    exec_payload = runtime_assignment_payload(
      mode: "deterministic_tool",
      task_payload: {
        "tool_name" => "exec_command",
        "command_line" => "cat",
        "pty" => true,
      },
      agent_context: default_agent_context.merge(
        "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[exec_command write_stdin]
      )
    )
    exec_payload.fetch("payload").fetch("task")["agent_task_run_id"] = agent_task_run_id

    started = Fenix::Runtime::ExecuteAssignment.call(mailbox_item: exec_payload, control_client: control_client)

    attached_invocation = started.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)
    command_run_id = attached_invocation.dig("response_payload", "command_run_id")
    attached_pid = Fenix::Runtime::CommandRunRegistry.lookup(command_run_id: command_run_id)&.wait_thread&.pid

    assert_equal "completed", started.status
    assert_equal "Command run started.", started.output
    assert command_run_id.present?
    assert attached_pid.present?

    write_payload = runtime_assignment_payload(
      mode: "deterministic_tool",
      task_payload: {
        "tool_name" => "write_stdin",
        "command_run_id" => command_run_id,
        "text" => "hello\n",
        "eof" => true,
        "wait_for_exit" => true,
      },
      agent_context: default_agent_context.merge(
        "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[exec_command write_stdin]
      )
    )
    write_payload.fetch("payload").fetch("task")["agent_task_run_id"] = agent_task_run_id

    finished = Fenix::Runtime::ExecuteAssignment.call(mailbox_item: write_payload, control_client: control_client)

    output_progress = finished.reports.find do |report|
      report.dig("progress_payload", "tool_invocation_output").present?
    end.fetch("progress_payload").fetch("tool_invocation_output")
    completed_invocation = finished.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "completed", finished.status
    assert_equal "Command run completed with status 0 after streaming output.", finished.output
    assert_equal command_run_id, output_progress.fetch("command_run_id")
    assert_equal "stdout", output_progress.fetch("output_chunks").fetch(0).fetch("stream")
    assert_equal "hello\n", output_progress.fetch("output_chunks").fetch(0).fetch("text")
    assert_equal "write_stdin", completed_invocation.fetch("tool_name")
    assert_equal command_run_id, completed_invocation.dig("response_payload", "command_run_id")
    assert_equal 0, completed_invocation.dig("response_payload", "exit_status")
    assert_equal true, completed_invocation.dig("response_payload", "session_closed")
    assert_equal 6, completed_invocation.dig("response_payload", "stdout_bytes")
    refute completed_invocation.fetch("response_payload").key?("stdout")
    refute completed_invocation.fetch("response_payload").key?("stderr")
    released_snapshot = Fenix::Runtime::CommandRunRegistry.output_snapshot(command_run_id: command_run_id)
    assert_equal "stopped", released_snapshot.fetch("lifecycle_state")
    assert_equal true, released_snapshot.fetch("session_closed")
    assert_equal 0, released_snapshot.fetch("exit_status")
    assert_equal "hello\n", released_snapshot.fetch("stdout_tail")
    assert_process_terminated(attached_pid)
  end

  test "write_stdin completes when an attached command emits binary output" do
    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      previous_workspace_root = ENV["FENIX_WORKSPACE_ROOT"]
      ENV["FENIX_WORKSPACE_ROOT"] = workspace_root
      File.binwrite(File.join(workspace_root, "logo.png"), "\x89PNG\r\n\x1A\nbinary".b)

      agent_task_run_id = "task-#{SecureRandom.uuid}"
      control_client = build_runtime_control_client

      exec_payload = runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "exec_command",
          "command_line" => "cat logo.png",
          "pty" => true,
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[exec_command write_stdin]
        )
      )
      exec_payload.fetch("payload").fetch("task")["agent_task_run_id"] = agent_task_run_id

      started = Fenix::Runtime::ExecuteAssignment.call(mailbox_item: exec_payload, control_client: control_client)
      command_run_id = started.reports.last
        .fetch("terminal_payload")
        .fetch("tool_invocations")
        .fetch(0)
        .dig("response_payload", "command_run_id")

      write_payload = runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "write_stdin",
          "command_run_id" => command_run_id,
          "text" => "",
          "eof" => true,
          "wait_for_exit" => true,
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[exec_command write_stdin]
        )
      )
      write_payload.fetch("payload").fetch("task")["agent_task_run_id"] = agent_task_run_id

      finished = Fenix::Runtime::ExecuteAssignment.call(mailbox_item: write_payload, control_client: control_client)
      completed_invocation = finished.reports.last
        .fetch("terminal_payload")
        .fetch("tool_invocations")
        .fetch(0)
      output_progress = finished.reports.find do |report|
        report.dig("progress_payload", "tool_invocation_output").present?
      end.fetch("progress_payload").fetch("tool_invocation_output")
      released_snapshot = Fenix::Runtime::CommandRunRegistry.output_snapshot(command_run_id: command_run_id)

      assert_equal "completed", finished.status
      assert_equal true, completed_invocation.dig("response_payload", "session_closed")
      assert output_progress.fetch("output_chunks").all? { |chunk| chunk.fetch("text").valid_encoding? }
      assert released_snapshot.fetch("stdout_tail").valid_encoding?
    ensure
      ENV["FENIX_WORKSPACE_ROOT"] = previous_workspace_root
    end
  end

  test "write_stdin routes through the exec command plugin runtime" do
    agent_task_run_id = "task-#{SecureRandom.uuid}"
    routed_call = nil
    control_client = build_runtime_control_client

    exec_payload = runtime_assignment_payload(
      mode: "deterministic_tool",
      task_payload: {
        "tool_name" => "exec_command",
        "command_line" => "cat",
        "pty" => true,
      },
      agent_context: default_agent_context.merge(
        "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[exec_command write_stdin]
      )
    )
    exec_payload.fetch("payload").fetch("task")["agent_task_run_id"] = agent_task_run_id

    started = Fenix::Runtime::ExecuteAssignment.call(mailbox_item: exec_payload, control_client: control_client)
    command_run_id = started.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)
      .dig("response_payload", "command_run_id")

    original_call = Fenix::Plugins::System::ExecCommand::Runtime.method(:call)
    Fenix::Plugins::System::ExecCommand::Runtime.define_singleton_method(:call) do |**kwargs|
      routed_call = kwargs
      {
        "command_run_id" => kwargs.fetch(:tool_call).dig("arguments", "command_run_id"),
        "stdin_bytes" => 6,
        "session_closed" => true,
        "exit_status" => 0,
        "stdout_bytes" => 6,
        "stderr_bytes" => 0,
        "output_streamed" => true,
      }
    end

    begin
      write_payload = runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "write_stdin",
          "command_run_id" => command_run_id,
          "text" => "hello\n",
          "eof" => true,
          "wait_for_exit" => true,
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[exec_command write_stdin]
        )
      )
      write_payload.fetch("payload").fetch("task")["agent_task_run_id"] = agent_task_run_id

      result = Fenix::Runtime::ExecuteAssignment.call(mailbox_item: write_payload, control_client: control_client)
      assert_equal "completed", result.status
    ensure
      Fenix::Plugins::System::ExecCommand::Runtime.define_singleton_method(:call, original_call)
    end

    assert_equal "write_stdin", routed_call.fetch(:tool_call).fetch("tool_name")
    assert_equal command_run_id, routed_call.fetch(:tool_call).dig("arguments", "command_run_id")
    assert routed_call.fetch(:tool_invocation).fetch("tool_invocation_id").present?
  end

  test "process_exec provisions a background service through ProcessRun and keeps tool invocation flow empty" do
    control_client = build_runtime_control_client

    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "process_exec",
          "command_line" => "trap 'exit 0' TERM; while :; do sleep 1; done",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["process_exec"]
        )
      ),
      control_client: control_client
    )

    assert_equal "completed", result.status
    assert_equal %w[execution_started execution_complete],
      result.reports.map { |report| report.fetch("method_id") }

    terminal_payload = result.reports.last.fetch("terminal_payload")
    refute terminal_payload.key?("tool_invocations")
    assert_match(/Background service started as process run /, result.output)

    assert_equal [], control_client.tool_invocation_requests
    assert_equal [], control_client.command_run_requests
    assert_equal ["process_exec"], control_client.process_run_requests.map { |request| request.fetch("tool_name") }
    assert_equal ["background_service"], control_client.process_run_requests.map { |request| request.fetch("kind") }

    process_run_id = control_client.process_run_requests.first.dig("response", "process_run_id")
    started_report = control_client.reported_payloads.find { |payload| payload["method_id"] == "process_started" }

    assert_equal process_run_id, started_report.fetch("resource_id")
    assert_equal "ProcessRun", started_report.fetch("resource_type")
    assert Fenix::Processes::Manager.lookup(process_run_id: process_run_id).present?
  end

  test "exec_command remains supported when the active job adapter is solid_queue" do
    original_queue_adapter_name = ActiveJob::Base.method(:queue_adapter_name)
    ActiveJob::Base.singleton_class.define_method(:queue_adapter_name) { "solid_queue" }

    control_client = build_runtime_control_client
    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "exec_command",
          "command_line" => "printf 'hello\\n'",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[exec_command write_stdin]
        )
      ),
      control_client: control_client
    )

    assert_equal "completed", result.status
    assert_equal ["exec_command"], control_client.tool_invocation_requests.map { |request| request.fetch("tool_name") }
    assert_equal 1, control_client.command_run_requests.length
  ensure
    ActiveJob::Base.singleton_class.define_method(:queue_adapter_name, original_queue_adapter_name)
  end

  test "process_exec remains supported when the active job adapter is solid_queue" do
    original_queue_adapter_name = ActiveJob::Base.method(:queue_adapter_name)
    ActiveJob::Base.singleton_class.define_method(:queue_adapter_name) { "solid_queue" }

    control_client = build_runtime_control_client
    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "process_exec",
          "command_line" => "trap 'exit 0' TERM; while :; do sleep 1; done",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["process_exec"]
        )
      ),
      control_client: control_client
    )

    assert_equal "completed", result.status
    assert_equal ["process_exec"], control_client.process_run_requests.map { |request| request.fetch("tool_name") }
  ensure
    ActiveJob::Base.singleton_class.define_method(:queue_adapter_name, original_queue_adapter_name)
  end

  test "process_exec normalizes the process kind alias before provisioning" do
    control_client = build_runtime_control_client

    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "process_exec",
          "kind" => "process",
          "command_line" => "npm run preview -- --host 0.0.0.0 --port 4173",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["process_exec"]
        )
      ),
      control_client: control_client
    )

    assert_equal "completed", result.status
    assert_equal ["background_service"], control_client.process_run_requests.map { |request| request.fetch("kind") }
  end

  test "one-shot exec_command kills the spawned subprocess if command run activation is rejected" do
    control_client = build_runtime_control_client
    spawned_pid = nil

    control_client.define_singleton_method(:activate_command_run!) do |command_run_id:|
      entry = Fenix::Runtime::CommandRunRegistry.lookup(command_run_id: command_run_id)
      spawned_pid = entry.wait_thread.pid
      raise "HTTP 404: command run is no longer activatable"
    end

    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "exec_command",
          "command_line" => "trap '' TERM; while :; do sleep 1; done",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[exec_command write_stdin]
        )
      ),
      control_client: control_client
    )

    assert_equal "failed", result.status
    assert_match(/activatable/, result.error.fetch("last_error_summary"))
    assert_nil Fenix::Runtime::CommandRunRegistry.lookup(
      command_run_id: control_client.command_run_requests.dig(0, "response", "command_run_id")
    )
    assert spawned_pid.present?
    assert_process_terminated(spawned_pid)
  end

  test "attached exec_command kills the spawned subprocess if command run activation is rejected" do
    control_client = build_runtime_control_client
    spawned_pid = nil

    control_client.define_singleton_method(:activate_command_run!) do |command_run_id:|
      entry = Fenix::Runtime::CommandRunRegistry.lookup(command_run_id: command_run_id)
      spawned_pid = entry.wait_thread.pid
      raise "HTTP 404: command run is no longer activatable"
    end

    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "exec_command",
          "command_line" => "cat",
          "pty" => true,
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[exec_command write_stdin]
        )
      ),
      control_client: control_client
    )

    assert_equal "failed", result.status
    assert_match(/activatable/, result.error.fetch("last_error_summary"))
    assert_nil Fenix::Runtime::CommandRunRegistry.lookup(
      command_run_id: control_client.command_run_requests.dig(0, "response", "command_run_id")
    )
    assert spawned_pid.present?
    assert_process_terminated(spawned_pid)
  end

  test "core matrix model context triggers proactive context compaction before execution" do
    long_messages = 12.times.map do |index|
      { "role" => index.even? ? "user" : "assistant", "content" => "token token token token #{index}" }
    end

    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        context_messages: long_messages,
        budget_hints: { "advisory_hints" => { "recommended_compaction_threshold" => 8 } }
      )
    )

    compact_context_entry = result.trace.find { |entry| entry.fetch("hook") == "compact_context" }

    assert compact_context_entry.fetch("compacted")
    assert_equal "gpt-4.1-mini", compact_context_entry.fetch("likely_model")
    assert_operator compact_context_entry.fetch("after_message_count"), :<, compact_context_entry.fetch("before_message_count")
  end

  test "program assignment execution rejects non-program runtime planes" do
    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(runtime_plane: "execution")
    )

    assert_equal "failed", result.status
    assert_equal "unsupported_runtime_plane", result.error.fetch("failure_kind")
    assert_equal %w[execution_fail], result.reports.map { |report| report.fetch("method_id") }
  end

  test "deterministic tool execution fails when the calculator tool is masked out of the assignment context" do
    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => %w[compact_context estimate_messages estimate_tokens]
        )
      )
    )

    assert_equal "failed", result.status
    assert_equal "runtime_error", result.error.fetch("failure_kind")
    assert_match(/calculator/, result.error.fetch("last_error_summary"))
    assert_equal %w[execution_started execution_fail], result.reports.map { |report| report.fetch("method_id") }
    assert_equal %w[prepare_turn compact_context handle_error], result.trace.map { |entry| entry.fetch("hook") }

    failed_invocation = result.reports.find { |report| report.fetch("method_id") == "execution_fail" }
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "failed", failed_invocation.fetch("event")
    assert_equal "calculator", failed_invocation.fetch("tool_name")
    assert_equal "authorization", failed_invocation.dig("error_payload", "classification")
    assert_equal "tool_not_allowed", failed_invocation.dig("error_payload", "code")
  end

  test "shared core matrix execution assignment fixture completes successfully through the runtime path" do
    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: shared_contract_fixture("core_matrix_fenix_execution_assignment")
    )

    assert_equal "completed", result.status
    assert_equal "The calculator returned 4.", result.output
    assert_equal "gpt-5.4", result.trace.first.fetch("likely_model")
    assert_equal "researcher", result.trace.first.fetch("profile")
    assert result.reports.all? { |report| report.key?("protocol_message_id") }
  end

  private

  def assert_process_terminated(pid)
    deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2

    loop do
      begin
        Process.kill(0, pid)
      rescue Errno::ESRCH
        assert true
        return
      end

      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at

      sleep(0.05)
    end

    flunk "expected pid #{pid} to terminate"
  end
end
