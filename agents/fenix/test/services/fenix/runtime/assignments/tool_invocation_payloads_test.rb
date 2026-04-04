require "test_helper"

class Fenix::Runtime::Assignments::ToolInvocationPayloadsTest < ActiveSupport::TestCase
  test "builds the current tool invocation snapshot" do
    payload = Fenix::Runtime::Assignments::ToolInvocationPayloads.current(
      tool_call: {
        "call_id" => "call-123",
        "tool_name" => "calculator",
        "arguments" => { "expression" => "2 + 2" },
      },
      tool_invocation: { "tool_invocation_id" => "tool-invocation-1" },
      command_run: nil
    )

    assert_equal(
      {
        "tool_invocation_id" => "tool-invocation-1",
        "call_id" => "call-123",
        "tool_name" => "calculator",
        "request_payload" => {
          "tool_name" => "calculator",
          "arguments" => { "expression" => "2 + 2" },
        },
      },
      payload
    )
  end

  test "builds started and completed payloads from the current invocation snapshot" do
    current_tool_invocation = {
      "tool_invocation_id" => "tool-invocation-1",
      "command_run_id" => "command-run-1",
      "call_id" => "call-123",
      "tool_name" => "exec_command",
      "request_payload" => {
        "tool_name" => "exec_command",
        "arguments" => { "command_line" => "printf hello" },
      },
    }

    started = Fenix::Runtime::Assignments::ToolInvocationPayloads.started(current_tool_invocation)
    completed = Fenix::Runtime::Assignments::ToolInvocationPayloads.completed(
      current_tool_invocation:,
      response_payload: { "exit_status" => 0 }
    )

    assert_equal "started", started.fetch("event")
    assert_equal "exec_command", started.fetch("tool_name")
    assert_equal "command-run-1", started.fetch("command_run_id")
    assert_equal "completed", completed.fetch("event")
    assert_equal "exec_command", completed.fetch("tool_name")
    assert_equal({ "exit_status" => 0 }, completed.fetch("response_payload"))
  end

  test "builds failed payloads with the program tool error mapper" do
    error = StandardError.new("boom")
    current_tool_invocation = {
      "tool_invocation_id" => "tool-invocation-1",
      "call_id" => "call-123",
      "tool_name" => "calculator",
      "request_payload" => {
        "tool_name" => "calculator",
        "arguments" => { "expression" => "2 + 2" },
      },
    }

    payload = Fenix::Runtime::Assignments::ToolInvocationPayloads.failed(
      current_tool_invocation:,
      error:
    )

    assert_equal "failed", payload.fetch("event")
    assert_equal "calculator", payload.fetch("tool_name")
    assert_equal "runtime_error", payload.dig("error_payload", "code")
    assert_equal "boom", payload.dig("error_payload", "message")
  end
end
