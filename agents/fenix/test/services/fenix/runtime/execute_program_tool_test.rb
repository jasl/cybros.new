require "test_helper"
require "tmpdir"

class Fenix::Runtime::ExecuteProgramToolTest < ActiveSupport::TestCase
  test "executes compact_context through the program tool path" do
    response = Fenix::Runtime::ExecuteProgramTool.call(
      payload: {
        "task" => {
          "workflow_node_id" => "workflow-node-1",
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "kind" => "turn_step",
        },
        "agent_context" => {
          "profile" => "main",
          "allowed_tool_names" => %w[compact_context],
        },
        "provider_context" => {},
        "runtime_context" => {
          "agent_program_version_id" => "agent-program-version-1",
        },
        "program_tool_call" => {
          "call_id" => "tool-call-compact-1",
          "tool_name" => "compact_context",
          "arguments" => {
            "messages" => [
              { "role" => "system", "content" => "Base instructions" },
              { "role" => "user", "content" => "Older context " * 20 },
              { "role" => "assistant", "content" => "More old context " * 20 },
              { "role" => "user", "content" => "Newest request" },
            ],
            "budget_hints" => {
              "advisory_compaction_threshold_tokens" => 40,
            },
          },
        },
      }
    )

    assert_equal "ok", response.fetch("status")
    assert_equal "compact_context", response.dig("program_tool_call", "tool_name")
    assert_operator response.dig("result", "messages").size, :<=, 4
    assert_includes response.dig("result", "messages").map { |entry| entry.fetch("content") }.join("\n"), "Earlier context compacted"
  end

  test "returns a structured failure when the tool is not visible for this execution" do
    response = Fenix::Runtime::ExecuteProgramTool.call(
      payload: {
        "task" => {
          "workflow_node_id" => "workflow-node-1",
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "kind" => "turn_step",
        },
        "agent_context" => {
          "profile" => "main",
          "allowed_tool_names" => [],
        },
        "provider_context" => {},
        "runtime_context" => {
          "agent_program_version_id" => "agent-program-version-1",
        },
        "program_tool_call" => {
          "call_id" => "tool-call-compact-hidden-1",
          "tool_name" => "compact_context",
          "arguments" => {
            "messages" => [
              { "role" => "user", "content" => "Do a compact." },
            ],
            "budget_hints" => {},
          },
        },
      }
    )

    assert_equal "failed", response.fetch("status")
    assert_equal "tool_not_allowed", response.dig("failure", "code")
  end

  test "executes registry-backed executor tools through the program tool path" do
    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      response = Fenix::Runtime::ExecuteProgramTool.call(
        payload: {
          "task" => {
            "workflow_node_id" => "workflow-node-1",
            "conversation_id" => "conversation-1",
            "turn_id" => "turn-1",
            "kind" => "turn_step",
          },
          "agent_context" => {
            "profile" => "main",
            "allowed_tool_names" => %w[exec_command],
          },
          "provider_context" => {},
          "runtime_context" => {
            "agent_program_version_id" => "agent-program-version-1",
          },
          "workspace_context" => {
            "workspace_root" => workspace_root,
          },
          "program_tool_call" => {
            "call_id" => "tool-call-exec-command-1",
            "tool_name" => "exec_command",
            "arguments" => {
              "command_line" => "printf 'hello\\n'",
            },
          },
        }
      )

      assert_equal "ok", response.fetch("status")
      assert_equal "exec_command", response.dig("program_tool_call", "tool_name")
      assert_equal 0, response.dig("result", "exit_status")
      assert_equal 6, response.dig("result", "stdout_bytes")
      assert_operator response.fetch("output_chunks").length, :>=, 1
    end
  end

  test "executes process_exec through the program tool path with the provided process run ref" do
    processes_module_created = false

    unless Fenix.const_defined?(:Processes, false)
      Fenix.const_set(:Processes, Module.new)
      processes_module_created = true
    end

    processes_module = Fenix.const_get(:Processes)
    original_launcher = processes_module.const_get(:Launcher) if processes_module.const_defined?(:Launcher, false)

    processes_module.send(:remove_const, :Launcher) if processes_module.const_defined?(:Launcher, false)
    processes_module.const_set(
      :Launcher,
      Class.new do
        class << self
          attr_accessor :calls
        end

        self.calls = []

        define_singleton_method(:call) do |**kwargs|
          self.calls << kwargs.deep_stringify_keys
          {
            "process_run_id" => kwargs.fetch(:process_run).fetch("process_run_id"),
            "lifecycle_state" => "running",
          }
        end
      end
    )

    response = Fenix::Runtime::ExecuteProgramTool.call(
      payload: {
        "task" => {
          "workflow_node_id" => "workflow-node-1",
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "kind" => "turn_step",
        },
        "agent_context" => {
          "profile" => "main",
          "allowed_tool_names" => %w[process_exec],
        },
        "provider_context" => {},
        "runtime_context" => {
          "agent_program_version_id" => "agent-program-version-1",
        },
        "program_tool_call" => {
          "call_id" => "tool-call-process-exec-1",
          "tool_name" => "process_exec",
          "arguments" => {
            "command_line" => "bin/dev",
            "kind" => "background_service",
          },
        },
        "runtime_resource_refs" => {
          "process_run" => {
            "process_run_id" => "process-run-1",
            "runtime_owner_id" => "turn-1",
          },
        },
      }
    )

    assert_equal "ok", response.fetch("status")
    assert_equal "process_exec", response.dig("program_tool_call", "tool_name")
    assert_equal "process-run-1", response.dig("result", "process_run_id")
    assert_equal "running", response.dig("result", "lifecycle_state")
    assert_equal "process-run-1", processes_module.const_get(:Launcher).calls.first.dig("process_run", "process_run_id")
  ensure
    if Fenix.const_defined?(:Processes, false)
      current_processes_module = Fenix.const_get(:Processes)
      current_processes_module.send(:remove_const, :Launcher) if current_processes_module.const_defined?(:Launcher, false)
      current_processes_module.const_set(:Launcher, original_launcher) if defined?(original_launcher) && original_launcher
      Fenix.send(:remove_const, :Processes) if processes_module_created
    end
  end
end
