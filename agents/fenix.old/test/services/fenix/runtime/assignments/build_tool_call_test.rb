require "test_helper"

class Fenix::Runtime::Assignments::BuildToolCallTest < ActiveSupport::TestCase
  test "builds calculator calls with the default expression" do
    tool_call = Fenix::Runtime::Assignments::BuildToolCall.call(task_payload: {})

    assert_equal "calculator", tool_call.fetch("tool_name")
    assert_equal({ "expression" => "2 + 2" }, tool_call.fetch("arguments"))
    assert_match(/\Atool-call-/, tool_call.fetch("call_id"))
  end

  test "builds exec_command calls with explicit runtime options" do
    tool_call = Fenix::Runtime::Assignments::BuildToolCall.call(
      task_payload: {
        "tool_name" => "exec_command",
        "command_line" => "bin/test",
        "timeout_seconds" => 12,
        "pty" => true,
      }
    )

    assert_equal "exec_command", tool_call.fetch("tool_name")
    assert_equal(
      {
        "command_line" => "bin/test",
        "timeout_seconds" => 12,
        "pty" => true,
      },
      tool_call.fetch("arguments")
    )
  end

  test "builds shared search calls with default provider and limit" do
    tool_call = Fenix::Runtime::Assignments::BuildToolCall.call(
      task_payload: {
        "tool_name" => "web_search",
        "query" => "fenix",
      }
    )

    assert_equal "web_search", tool_call.fetch("tool_name")
    assert_equal(
      {
        "query" => "fenix",
        "limit" => 5,
        "provider" => "firecrawl",
      },
      tool_call.fetch("arguments")
    )
  end

  test "builds browser screenshot calls with full_page defaulting to true" do
    tool_call = Fenix::Runtime::Assignments::BuildToolCall.call(
      task_payload: {
        "tool_name" => "browser_screenshot",
        "browser_session_id" => "browser-1",
      }
    )

    assert_equal(
      {
        "browser_session_id" => "browser-1",
        "full_page" => true,
      },
      tool_call.fetch("arguments")
    )
  end

  test "builds process_exec calls with the default background service kind" do
    tool_call = Fenix::Runtime::Assignments::BuildToolCall.call(
      task_payload: {
        "tool_name" => "process_exec",
        "command_line" => "bin/dev",
        "proxy_port" => 4173,
      }
    )

    assert_equal(
      {
        "command_line" => "bin/dev",
        "kind" => "background_service",
        "proxy_port" => 4173,
      },
      tool_call.fetch("arguments")
    )
  end

  test "builds command run wait calls with command_run_id and default timeout" do
    tool_call = Fenix::Runtime::Assignments::BuildToolCall.call(
      task_payload: {
        "tool_name" => "command_run_wait",
        "command_run_id" => "command-run-1",
      }
    )

    assert_equal(
      {
        "command_run_id" => "command-run-1",
        "timeout_seconds" => 30,
      },
      tool_call.fetch("arguments")
    )
  end
end
