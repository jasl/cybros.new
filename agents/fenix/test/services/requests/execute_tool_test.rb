require "test_helper"

class Requests::ExecuteToolTest < ActiveSupport::TestCase
  test "executes the shared calculator contract fixture" do
    fixture_payload = JSON.parse(
      File.read(
        Rails.root.join("..", "..", "shared", "fixtures", "contracts", "core_matrix_fenix_execute_tool_mailbox_item.json")
      )
    ).fetch("payload")

    response = Requests::ExecuteTool.call(payload: fixture_payload)

    assert_equal "ok", response.fetch("status")
    assert_equal "calculator", response.dig("tool_call", "tool_name")
    assert_equal({ "value" => 4 }, response.fetch("result"))
    assert_equal [], response.fetch("output_chunks")
    assert_equal [], response.fetch("summary_artifacts")
  end

  test "delegates system tool execution through an injected boundary" do
    payload = {
      "task" => {
        "workflow_node_id" => "workflow-node-public-id",
        "conversation_id" => "conversation-public-id",
        "turn_id" => "turn-public-id",
        "kind" => "turn_step",
      },
      "agent_context" => {
        "allowed_tool_names" => ["exec_command"],
      },
      "tool_call" => {
        "tool_name" => "exec_command",
        "arguments" => { "command" => "pwd" },
      },
      "runtime_resource_refs" => {
        "command_run" => nil,
        "process_run" => nil,
      },
    }

    captured = nil
    response = Requests::ExecuteTool.call(
      payload: payload,
      supported_system_tool_names: ["exec_command"],
      system_tool_executor: lambda do |payload_context:, tool_call:, runtime_resource_refs:|
        captured = {
          payload_context: payload_context,
          tool_call: tool_call,
          runtime_resource_refs: runtime_resource_refs,
        }

        Struct.new(:tool_result, :output_chunks).new(
          { "exit_status" => 0, "stdout" => "/tmp\n", "stderr" => "" },
          []
        )
      end
    )

    assert_equal "ok", response.fetch("status")
    assert_equal "exec_command", captured.dig(:tool_call, "tool_name")
    assert_equal "conversation-public-id", captured.dig(:payload_context, "conversation_id")
    assert_equal({ "exit_status" => 0, "stdout" => "/tmp\n", "stderr" => "" }, response.fetch("result"))
  end
end
