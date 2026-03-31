require "test_helper"

class Fenix::Runtime::ProgramToolExecutorTest < ActiveSupport::TestCase
  test "executes calculator through the shared program executor" do
    executor = Fenix::Runtime::ProgramToolExecutor.new(
      context: {
        "workflow_node_id" => "workflow-node-1",
        "conversation_id" => "conversation-1",
        "turn_id" => "turn-1",
        "agent_context" => { "allowed_tool_names" => ["calculator"] },
        "workspace_context" => { "workspace_root" => Fenix::Workspace::Layout.default_root },
      }
    )

    result = executor.call(
      tool_call: {
        "call_id" => "tool-call-1",
        "tool_name" => "calculator",
        "arguments" => { "expression" => "2 + 2" },
      }
    )

    assert_equal "calculator", result.tool_call.fetch("tool_name")
    assert_equal 4, result.tool_result
    assert_equal [], result.output_chunks
  end

  test "captures streamed output for exec command without using the control plane" do
    executor = Fenix::Runtime::ProgramToolExecutor.new(
      context: {
        "workflow_node_id" => "workflow-node-1",
        "conversation_id" => "conversation-1",
        "turn_id" => "turn-1",
        "agent_context" => { "allowed_tool_names" => ["exec_command"] },
        "workspace_context" => { "workspace_root" => Fenix::Workspace::Layout.default_root },
      }
    )

    result = executor.call(
      tool_call: {
        "call_id" => "tool-call-1",
        "tool_name" => "exec_command",
        "arguments" => {
          "command_line" => "printf 'hello\\n'",
          "timeout_seconds" => 5,
          "pty" => false,
        },
      },
      command_run: {
        "command_run_id" => "command-run-1",
      }
    )

    assert_equal "exec_command", result.tool_call.fetch("tool_name")
    assert_equal "command-run-1", result.tool_result.fetch("command_run_id")
    assert_equal 0, result.tool_result.fetch("exit_status")
    assert_equal "stdout", result.output_chunks.first.fetch("stream")
    assert_equal "hello\n", result.output_chunks.first.fetch("text")
  end

  test "exec_command runs relative to the workspace root" do
    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      executor = Fenix::Runtime::ProgramToolExecutor.new(
        context: {
          "workflow_node_id" => "workflow-node-1",
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "agent_context" => { "allowed_tool_names" => ["exec_command"] },
          "workspace_context" => { "workspace_root" => workspace_root },
        }
      )

      result = executor.call(
        tool_call: {
          "call_id" => "tool-call-2",
          "tool_name" => "exec_command",
          "arguments" => {
            "command_line" => "pwd",
            "timeout_seconds" => 5,
            "pty" => false,
          },
        },
        command_run: {
          "command_run_id" => "command-run-2",
        }
      )

      assert_equal Pathname.new(workspace_root).realpath.to_s, Pathname.new(result.tool_result.fetch("stdout").strip).realpath.to_s
    end
  end
end
