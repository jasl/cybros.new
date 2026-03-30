require "test_helper"

class Fenix::Runtime::ExecuteAssignmentTest < ActiveSupport::TestCase
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

  test "shell_exec emits tool output progress and completes with structured command results" do
    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "shell_exec",
          "command_line" => "printf 'hello\\n'",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["shell_exec"]
        )
      )
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

    assert_equal "shell_exec", started_invocation.fetch("tool_name")
    assert_equal started_invocation.fetch("call_id"), output_progress.fetch("call_id")
    assert_equal "stdout", output_progress.fetch("output_chunks").fetch(0).fetch("stream")
    assert_equal "hello\n", output_progress.fetch("output_chunks").fetch(0).fetch("text")
    assert_equal "completed", completed_invocation.fetch("event")
    assert_equal "shell_exec", completed_invocation.fetch("tool_name")
    assert_equal "Command exited with status 0 after streaming output.", result.output
    assert_equal 0, completed_invocation.dig("response_payload", "exit_status")
    assert_equal true, completed_invocation.dig("response_payload", "output_streamed")
    assert_equal 6, completed_invocation.dig("response_payload", "stdout_bytes")
    assert_equal 0, completed_invocation.dig("response_payload", "stderr_bytes")
    refute completed_invocation.fetch("response_payload").key?("stdout")
    refute completed_invocation.fetch("response_payload").key?("stderr")
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

  test "agent assignment execution rejects non-agent runtime planes" do
    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(runtime_plane: "environment")
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
      mailbox_item: shared_contract_fixture("core_matrix_fenix_execution_assignment_v1")
    )

    assert_equal "completed", result.status
    assert_equal "The calculator returned 4.", result.output
    assert_equal "gpt-5.4", result.trace.first.fetch("likely_model")
    assert_equal "researcher", result.trace.first.fetch("profile")
    assert result.reports.all? { |report| report.key?("protocol_message_id") }
  end
end
