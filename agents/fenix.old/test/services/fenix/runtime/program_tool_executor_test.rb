require "test_helper"
require "timeout"

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

  test "one-shot exec_command scrubs binary output into UTF-8-safe text" do
    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      binary_bytes = "\x89PNG\r\n\x1A\nbinary".b
      File.binwrite(File.join(workspace_root, "logo.png"), binary_bytes)

      executor = Fenix::Runtime::ProgramToolExecutor.new(
        context: {
          "workflow_node_id" => "workflow-node-binary-1",
          "conversation_id" => "conversation-binary-1",
          "turn_id" => "turn-binary-1",
          "agent_context" => { "allowed_tool_names" => ["exec_command"] },
          "workspace_context" => { "workspace_root" => workspace_root },
        }
      )

      result = executor.call(
        tool_call: {
          "call_id" => "tool-call-binary-1",
          "tool_name" => "exec_command",
          "arguments" => {
            "command_line" => "cat logo.png",
            "timeout_seconds" => 5,
            "pty" => false,
          },
        },
        command_run: {
          "command_run_id" => "command-run-binary-1",
        }
      )

      assert_equal binary_bytes.bytesize, result.tool_result.fetch("stdout_bytes")
      assert result.tool_result.fetch("stdout").valid_encoding?
      assert_equal Encoding::UTF_8, result.tool_result.fetch("stdout").encoding
      assert result.output_chunks.all? { |chunk| chunk.fetch("text").valid_encoding? }
    end
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

  test "times out one-shot exec_command even when the command spawns a child shell" do
    executor = Fenix::Runtime::ProgramToolExecutor.new(
      context: {
        "agent_task_run_id" => "task-1",
        "workflow_node_id" => "workflow-node-1",
        "conversation_id" => "conversation-1",
        "turn_id" => "turn-1",
        "agent_context" => { "allowed_tool_names" => ["exec_command"] },
        "workspace_context" => { "workspace_root" => Dir.pwd },
      }
    )

    error = assert_raises(Timeout::Error) do
      Timeout.timeout(4) do
        executor.call(
          tool_call: {
            "call_id" => "tool-call-timeout-1",
            "tool_name" => "exec_command",
            "arguments" => {
              "command_line" => "sh -c 'while :; do sleep 1; done'",
              "timeout_seconds" => 1,
              "pty" => false,
            },
          },
          command_run: {
            "command_run_id" => "command-run-timeout-1",
          }
        )
      end
    end

    assert_match(/exec_command timed out after 1 seconds/, error.message)
    assert_nil Fenix::Runtime::CommandRunRegistry.lookup(command_run_id: "command-run-timeout-1")
  end

  test "process_exec tolerates the default null control client" do
    original_call = Fenix::Processes::Launcher.method(:call)
    routed_control_client = nil

    Fenix::Processes::Launcher.define_singleton_method(:call) do |**kwargs|
      routed_control_client = kwargs.fetch(:control_client)
      kwargs.fetch(:control_client).report!(payload: { "method_id" => "process_started" })
      {
        "process_run_id" => kwargs.fetch(:process_run).fetch("process_run_id"),
        "lifecycle_state" => "running",
      }
    end

    executor = Fenix::Runtime::ProgramToolExecutor.new(
      context: {
        "workflow_node_id" => "workflow-node-1",
        "conversation_id" => "conversation-1",
        "turn_id" => "turn-1",
        "agent_context" => { "allowed_tool_names" => ["process_exec"] },
        "workspace_context" => { "workspace_root" => Fenix::Workspace::Layout.default_root },
      }
    )

    result = executor.call(
      tool_call: {
        "call_id" => "tool-call-3",
        "tool_name" => "process_exec",
        "arguments" => {
          "command_line" => "bin/dev",
        },
      },
      process_run: {
        "process_run_id" => "process-run-1",
      }
    )

    assert_equal "process_exec", result.tool_call.fetch("tool_name")
    assert_equal "process-run-1", result.tool_result.fetch("process_run_id")
    assert_equal "running", result.tool_result.fetch("lifecycle_state")
    assert_respond_to routed_control_client, :report!
  ensure
    Fenix::Processes::Launcher.define_singleton_method(:call, original_call)
  end

  test "attached command runs stay reusable across workflow nodes within the same turn" do
    starting_executor = Fenix::Runtime::ProgramToolExecutor.new(
      context: {
        "workflow_node_id" => "workflow-node-1",
        "conversation_id" => "conversation-1",
        "turn_id" => "turn-1",
        "agent_context" => {
          "allowed_tool_names" => %w[exec_command write_stdin],
        },
        "workspace_context" => { "workspace_root" => Fenix::Workspace::Layout.default_root },
      }
    )

    started = starting_executor.call(
      tool_call: {
        "call_id" => "tool-call-attached-1",
        "tool_name" => "exec_command",
        "arguments" => {
          "command_line" => "cat",
          "pty" => true,
        },
      },
      command_run: {
        "command_run_id" => "command-run-attached-1",
      }
    )

    continuing_executor = Fenix::Runtime::ProgramToolExecutor.new(
      context: {
        "workflow_node_id" => "workflow-node-2",
        "conversation_id" => "conversation-1",
        "turn_id" => "turn-1",
        "agent_context" => {
          "allowed_tool_names" => %w[exec_command write_stdin],
        },
        "workspace_context" => { "workspace_root" => Fenix::Workspace::Layout.default_root },
      }
    )

    finished = continuing_executor.call(
      tool_call: {
        "call_id" => "tool-call-attached-2",
        "tool_name" => "write_stdin",
        "arguments" => {
          "command_run_id" => started.tool_result.fetch("command_run_id"),
          "text" => "hello\n",
          "eof" => true,
          "wait_for_exit" => true,
        },
      }
    )

    assert_equal "command-run-attached-1", finished.tool_result.fetch("command_run_id")
    assert_equal 0, finished.tool_result.fetch("exit_status")
    assert_equal true, finished.tool_result.fetch("session_closed")
    assert_equal "hello\n", finished.tool_result.fetch("stdout_tail")
  end

  test "write_stdin wait_for_exit scrubs binary attached output into UTF-8-safe text" do
    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      binary_bytes = "\x89PNG\r\n\x1A\nbinary".b
      File.binwrite(File.join(workspace_root, "logo.png"), binary_bytes)

      starting_executor = Fenix::Runtime::ProgramToolExecutor.new(
        context: {
          "workflow_node_id" => "workflow-node-binary-attached-1",
          "conversation_id" => "conversation-binary-attached-1",
          "turn_id" => "turn-binary-attached-1",
          "agent_context" => {
            "allowed_tool_names" => %w[exec_command write_stdin],
          },
          "workspace_context" => { "workspace_root" => workspace_root },
        }
      )

      started = starting_executor.call(
        tool_call: {
          "call_id" => "tool-call-binary-attached-1",
          "tool_name" => "exec_command",
          "arguments" => {
            "command_line" => "cat logo.png",
            "pty" => true,
          },
        },
        command_run: {
          "command_run_id" => "command-run-binary-attached-1",
        }
      )

      finishing_executor = Fenix::Runtime::ProgramToolExecutor.new(
        context: {
          "workflow_node_id" => "workflow-node-binary-attached-2",
          "conversation_id" => "conversation-binary-attached-1",
          "turn_id" => "turn-binary-attached-1",
          "agent_context" => {
            "allowed_tool_names" => %w[exec_command write_stdin],
          },
          "workspace_context" => { "workspace_root" => workspace_root },
        }
      )

      finished = finishing_executor.call(
        tool_call: {
          "call_id" => "tool-call-binary-attached-2",
          "tool_name" => "write_stdin",
          "arguments" => {
            "command_run_id" => started.tool_result.fetch("command_run_id"),
            "text" => "",
            "eof" => true,
            "wait_for_exit" => true,
          },
        }
      )

      assert_equal binary_bytes.bytesize, finished.tool_result.fetch("stdout_bytes")
      assert finished.tool_result.fetch("stdout_tail").valid_encoding?
      assert_equal Encoding::UTF_8, finished.tool_result.fetch("stdout_tail").encoding
      assert finished.output_chunks.all? { |chunk| chunk.fetch("text").valid_encoding? }
    end
  end

  test "command_run_wait times out promptly for attached commands and keeps the handle available" do
    starting_executor = Fenix::Runtime::ProgramToolExecutor.new(
      context: {
        "workflow_node_id" => "workflow-node-1",
        "conversation_id" => "conversation-1",
        "turn_id" => "turn-1",
        "agent_context" => {
          "allowed_tool_names" => %w[exec_command command_run_wait command_run_terminate],
        },
        "workspace_context" => { "workspace_root" => Fenix::Workspace::Layout.default_root },
      }
    )

    started = starting_executor.call(
      tool_call: {
        "call_id" => "tool-call-attached-timeout-1",
        "tool_name" => "exec_command",
        "arguments" => {
          "command_line" => "trap '' TERM; while :; do sleep 1; done",
          "pty" => true,
        },
      },
      command_run: {
        "command_run_id" => "command-run-attached-timeout-1",
      }
    )
    command_run_id = started.tool_result.fetch("command_run_id")

    waiting_executor = Fenix::Runtime::ProgramToolExecutor.new(
      context: {
        "workflow_node_id" => "workflow-node-2",
        "conversation_id" => "conversation-1",
        "turn_id" => "turn-1",
        "agent_context" => {
          "allowed_tool_names" => %w[command_run_wait command_run_terminate],
        },
        "workspace_context" => { "workspace_root" => Fenix::Workspace::Layout.default_root },
      }
    )

    error = assert_raises(Timeout::Error) do
      Timeout.timeout(4) do
        waiting_executor.call(
          tool_call: {
            "call_id" => "tool-call-attached-timeout-2",
            "tool_name" => "command_run_wait",
            "arguments" => {
              "command_run_id" => command_run_id,
              "timeout_seconds" => 1,
            },
          }
        )
      end
    end

    assert_match(/timed out after 1 seconds/, error.message)

    snapshot = Fenix::Runtime::CommandRunRegistry.output_snapshot(command_run_id: command_run_id)
    assert_equal "running", snapshot.fetch("lifecycle_state")
    assert_equal false, snapshot.fetch("session_closed")
  ensure
    Fenix::Runtime::CommandRunRegistry.terminate(command_run_id:) if command_run_id.present?
  end

  test "write_stdin wait_for_exit times out promptly for attached commands and keeps the handle available" do
    starting_executor = Fenix::Runtime::ProgramToolExecutor.new(
      context: {
        "workflow_node_id" => "workflow-node-1",
        "conversation_id" => "conversation-1",
        "turn_id" => "turn-1",
        "agent_context" => {
          "allowed_tool_names" => %w[exec_command write_stdin command_run_terminate],
        },
        "workspace_context" => { "workspace_root" => Fenix::Workspace::Layout.default_root },
      }
    )

    started = starting_executor.call(
      tool_call: {
        "call_id" => "tool-call-attached-timeout-3",
        "tool_name" => "exec_command",
        "arguments" => {
          "command_line" => "cat >/dev/null; trap '' TERM; while :; do sleep 1; done",
          "pty" => true,
        },
      },
      command_run: {
        "command_run_id" => "command-run-attached-timeout-2",
      }
    )
    command_run_id = started.tool_result.fetch("command_run_id")

    writing_executor = Fenix::Runtime::ProgramToolExecutor.new(
      context: {
        "workflow_node_id" => "workflow-node-2",
        "conversation_id" => "conversation-1",
        "turn_id" => "turn-1",
        "agent_context" => {
          "allowed_tool_names" => %w[write_stdin command_run_terminate],
        },
        "workspace_context" => { "workspace_root" => Fenix::Workspace::Layout.default_root },
      }
    )

    error = assert_raises(Timeout::Error) do
      Timeout.timeout(4) do
        writing_executor.call(
          tool_call: {
            "call_id" => "tool-call-attached-timeout-4",
            "tool_name" => "write_stdin",
            "arguments" => {
              "command_run_id" => command_run_id,
              "text" => "hello\n",
              "eof" => true,
              "wait_for_exit" => true,
              "timeout_seconds" => 1,
            },
          }
        )
      end
    end

    assert_match(/timed out after 1 seconds/, error.message)

    snapshot = Fenix::Runtime::CommandRunRegistry.output_snapshot(command_run_id: command_run_id)
    assert_equal "running", snapshot.fetch("lifecycle_state")
    assert_equal false, snapshot.fetch("session_closed")
  ensure
    Fenix::Runtime::CommandRunRegistry.terminate(command_run_id:) if command_run_id.present?
  end

  test "browser tools use the turn as the stable execution owner when agent task run id is absent" do
    routed_owner_ids = []
    original_call = Fenix::Plugins::System::Browser::Runtime.method(:call)

    Fenix::Plugins::System::Browser::Runtime.define_singleton_method(:call) do |**kwargs|
      routed_owner_ids << kwargs.fetch(:current_agent_task_run_id)
      {
        "browser_session_id" => "browser-session-1",
        "current_url" => "https://example.com",
        "content" => "Example page",
      }
    end

    opening_executor = Fenix::Runtime::ProgramToolExecutor.new(
      context: {
        "workflow_node_id" => "workflow-node-1",
        "conversation_id" => "conversation-1",
        "turn_id" => "turn-1",
        "agent_context" => { "allowed_tool_names" => %w[browser_open browser_get_content] },
        "workspace_context" => { "workspace_root" => Fenix::Workspace::Layout.default_root },
      }
    )
    continuing_executor = Fenix::Runtime::ProgramToolExecutor.new(
      context: {
        "workflow_node_id" => "workflow-node-2",
        "conversation_id" => "conversation-1",
        "turn_id" => "turn-1",
        "agent_context" => { "allowed_tool_names" => %w[browser_open browser_get_content] },
        "workspace_context" => { "workspace_root" => Fenix::Workspace::Layout.default_root },
      }
    )

    opening_executor.call(
      tool_call: {
        "call_id" => "tool-call-browser-1",
        "tool_name" => "browser_open",
        "arguments" => { "url" => "https://example.com" },
      }
    )
    continuing_executor.call(
      tool_call: {
        "call_id" => "tool-call-browser-2",
        "tool_name" => "browser_get_content",
        "arguments" => { "browser_session_id" => "browser-session-1" },
      }
    )

    assert_equal %w[turn-1 turn-1], routed_owner_ids
  ensure
    Fenix::Plugins::System::Browser::Runtime.define_singleton_method(:call, original_call)
  end

  test "process tools use the turn as the stable execution owner when agent task run id is absent" do
    routed_process_run = nil
    routed_owner_ids = []
    original_call = Fenix::Plugins::System::Process::Runtime.method(:call)

    Fenix::Plugins::System::Process::Runtime.define_singleton_method(:call) do |**kwargs|
      routed_process_run = kwargs.fetch(:process_run)
      routed_owner_ids << kwargs.fetch(:current_agent_task_run_id)
      {
        "process_run_id" => kwargs.fetch(:process_run).fetch("process_run_id"),
        "lifecycle_state" => "running",
      }
    end

    executor = Fenix::Runtime::ProgramToolExecutor.new(
      context: {
        "workflow_node_id" => "workflow-node-1",
        "conversation_id" => "conversation-1",
        "turn_id" => "turn-1",
        "agent_context" => { "allowed_tool_names" => ["process_exec"] },
        "workspace_context" => { "workspace_root" => Fenix::Workspace::Layout.default_root },
      }
    )

    result = executor.call(
      tool_call: {
        "call_id" => "tool-call-process-1",
        "tool_name" => "process_exec",
        "arguments" => { "command_line" => "bin/dev" },
      }
    )

    assert_match(/\Aprocess-run-/, result.tool_result.fetch("process_run_id"))
    assert_equal %w[turn-1], routed_owner_ids
    assert_equal "turn-1", routed_process_run.fetch("agent_task_run_id")
  ensure
    Fenix::Plugins::System::Process::Runtime.define_singleton_method(:call, original_call)
  end
end
