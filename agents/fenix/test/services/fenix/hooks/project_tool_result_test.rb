require "test_helper"

class Fenix::Hooks::ProjectToolResultTest < ActiveSupport::TestCase
  test "projects exec command results through the registry projector" do
    projection = Fenix::Hooks::ProjectToolResult.call(
      tool_call: { "tool_name" => "exec_command" },
      tool_result: {
        "command_run_id" => "command-run-1",
        "exit_status" => 0,
        "stdout_bytes" => 6,
        "stderr_bytes" => 0,
        "output_streamed" => true,
      }
    )

    assert_equal "exec_command", projection.fetch("tool_name")
    assert_equal "command-run-1", projection.fetch("command_run_id")
    assert_match(/status 0/, projection.fetch("content"))
  end

  test "projects browser screenshot results through the registry projector" do
    projection = Fenix::Hooks::ProjectToolResult.call(
      tool_call: { "tool_name" => "browser_screenshot" },
      tool_result: {
        "browser_session_id" => "browser-session-1",
        "current_url" => "http://127.0.0.1:4173",
        "mime_type" => "image/png",
        "image_base64" => "cG5n",
      }
    )

    assert_equal "browser_screenshot", projection.fetch("tool_name")
    assert_equal "browser-session-1", projection.fetch("browser_session_id")
    assert_equal "image/png", projection.fetch("mime_type")
    assert_match(/Captured screenshot/, projection.fetch("content"))
  end

  test "projects detached process results through the registry projector" do
    projection = Fenix::Hooks::ProjectToolResult.call(
      tool_call: { "tool_name" => "process_exec" },
      tool_result: {
        "process_run_id" => "process-run-1",
        "lifecycle_state" => "running",
        "proxy_path" => "/dev/process-run-1",
      }
    )

    assert_equal "process_exec", projection.fetch("tool_name")
    assert_equal "process-run-1", projection.fetch("process_run_id")
    assert_match(%r{/dev/process-run-1}, projection.fetch("content"))
  end
end
