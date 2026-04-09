require "test_helper"

class FenixProcessToolResultProjectorTest < ActiveSupport::TestCase
  test "projects detached process tool results into agent-facing summaries" do
    started = Fenix::Hooks::ToolResultProjectors::Process.call(
      tool_name: "process_exec",
      tool_result: {
        "process_run_id" => "process-run-1",
        "lifecycle_state" => "running",
        "proxy_path" => "/dev/process-run-1",
        "proxy_target_url" => "http://127.0.0.1:4100",
      }
    )
    listed = Fenix::Hooks::ToolResultProjectors::Process.call(
      tool_name: "process_list",
      tool_result: {
        "entries" => [{ "process_run_id" => "process-run-1" }],
      }
    )
    output = Fenix::Hooks::ToolResultProjectors::Process.call(
      tool_name: "process_read_output",
      tool_result: {
        "process_run_id" => "process-run-1",
        "lifecycle_state" => "running",
        "stdout_tail" => "ready\n",
        "stderr_tail" => "",
        "stdout_bytes" => 6,
        "stderr_bytes" => 0,
      }
    )

    assert_equal "process-run-1", started.fetch("process_run_id")
    assert_includes started.fetch("content"), "/dev/process-run-1"
    assert_equal 1, listed.fetch("entries").size
    assert_equal "ready\n", output.fetch("stdout_tail")
  end
end
