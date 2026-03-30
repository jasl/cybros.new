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
end
