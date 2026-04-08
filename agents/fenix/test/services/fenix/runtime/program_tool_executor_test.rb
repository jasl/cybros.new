require "test_helper"
require "tmpdir"
require "timeout"

class Fenix::Runtime::ProgramToolExecutorTest < ActiveSupport::TestCase
  teardown do
    Fenix::Runtime::CommandRunRegistry.reset! if defined?(Fenix::Runtime::CommandRunRegistry)
  end

  test "captures streamed output for one-shot exec_command" do
    executor = build_executor(allowed_tool_names: ["exec_command"])

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
      executor = build_executor(
        allowed_tool_names: ["exec_command"],
        workspace_root: workspace_root
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

  test "attached command runs stay reusable across executor calls" do
    starting_executor = build_executor(allowed_tool_names: %w[exec_command write_stdin])

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

    continuing_executor = build_executor(allowed_tool_names: %w[exec_command write_stdin])

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

    assert_equal "command-run-attached-1", started.tool_result.fetch("command_run_id")
    assert_equal true, started.tool_result.fetch("attached")
    assert_equal true, finished.tool_result.fetch("session_closed")
    assert_equal 0, finished.tool_result.fetch("exit_status")
    assert_equal "stdout", finished.output_chunks.first.fetch("stream")
    assert_equal "hello\n", finished.output_chunks.first.fetch("text")
  end

  test "command_run_wait returns a timed out snapshot while an attached command is still running" do
    executor = build_executor(allowed_tool_names: %w[exec_command command_run_wait])

    started = executor.call(
      tool_call: {
        "call_id" => "tool-call-attached-timeout-1",
        "tool_name" => "exec_command",
        "arguments" => {
          "command_line" => "sleep 2",
          "pty" => true,
        },
      },
      command_run: {
        "command_run_id" => "command-run-attached-timeout-1",
      }
    )

    waiting = executor.call(
      tool_call: {
        "call_id" => "tool-call-attached-timeout-2",
        "tool_name" => "command_run_wait",
        "arguments" => {
          "command_run_id" => started.tool_result.fetch("command_run_id"),
          "timeout_seconds" => 1,
        },
      }
    )

    assert_equal "command-run-attached-timeout-1", waiting.tool_result.fetch("command_run_id")
    assert_equal false, waiting.tool_result.fetch("session_closed")
    assert_equal true, waiting.tool_result.fetch("timed_out")
    assert_equal "running", waiting.tool_result.fetch("lifecycle_state")
  end

  test "command run list read output and terminate operate on owned local handles" do
    executor = build_executor(
      allowed_tool_names: %w[exec_command command_run_list command_run_read_output command_run_terminate]
    )

    started = executor.call(
      tool_call: {
        "call_id" => "tool-call-list-1",
        "tool_name" => "exec_command",
        "arguments" => {
          "command_line" => "printf 'ready\\n'; cat",
          "pty" => true,
        },
      },
      command_run: {
        "command_run_id" => "command-run-list-1",
      }
    )

    read = executor.call(
      tool_call: {
        "call_id" => "tool-call-list-2",
        "tool_name" => "command_run_read_output",
        "arguments" => {
          "command_run_id" => started.tool_result.fetch("command_run_id"),
        },
      }
    )

    listed = executor.call(
      tool_call: {
        "call_id" => "tool-call-list-3",
        "tool_name" => "command_run_list",
        "arguments" => {},
      }
    )

    terminated = executor.call(
      tool_call: {
        "call_id" => "tool-call-list-4",
        "tool_name" => "command_run_terminate",
        "arguments" => {
          "command_run_id" => started.tool_result.fetch("command_run_id"),
        },
      }
    )

    assert_equal "command-run-list-1", read.tool_result.fetch("command_run_id")
    assert_includes read.tool_result.fetch("stdout_tail"), "ready"
    assert_equal ["command-run-list-1"], listed.tool_result.fetch("entries").map { |entry| entry.fetch("command_run_id") }
    assert_equal true, terminated.tool_result.fetch("terminated")
    assert_equal true, terminated.tool_result.fetch("session_closed")
  end

  test "one-shot exec_command does not leave a listed local handle behind" do
    executor = build_executor(
      allowed_tool_names: %w[exec_command command_run_list]
    )

    executor.call(
      tool_call: {
        "call_id" => "tool-call-one-shot-1",
        "tool_name" => "exec_command",
        "arguments" => {
          "command_line" => "printf 'done\\n'",
          "timeout_seconds" => 5,
          "pty" => false,
        },
      }
    )

    listed = executor.call(
      tool_call: {
        "call_id" => "tool-call-one-shot-2",
        "tool_name" => "command_run_list",
        "arguments" => {},
      }
    )

    assert_equal [], listed.tool_result.fetch("entries")
  end

  test "raises when the tool is not visible for this execution" do
    executor = build_executor(allowed_tool_names: [])

    error = assert_raises(Fenix::Runtime::ProgramToolExecutor::ToolNotAllowedError) do
      executor.call(
        tool_call: {
          "call_id" => "tool-call-hidden-1",
          "tool_name" => "exec_command",
          "arguments" => {
            "command_line" => "pwd",
          },
        }
      )
    end

    assert_match(/tool exec_command is not visible/i, error.message)
    assert_equal "tool_not_allowed", Fenix::Runtime::ProgramToolExecutor.error_payload_for(error).fetch("code")
  end

  test "maps command validation failures to semantic error payloads" do
    executor = build_executor(allowed_tool_names: ["command_run_read_output"])

    error = assert_raises(Fenix::Runtime::ToolExecutors::ExecCommand::ValidationError) do
      executor.call(
        tool_call: {
          "call_id" => "tool-call-missing-1",
          "tool_name" => "command_run_read_output",
          "arguments" => {
            "command_run_id" => "missing-command-run",
          },
        }
      )
    end

    assert_equal "validation_error", Fenix::Runtime::ProgramToolExecutor.error_payload_for(error).fetch("code")
  end

  test "routes browser tools through the browser session manager" do
    executor = build_executor(
      allowed_tool_names: %w[
        browser_open
        browser_navigate
        browser_get_content
        browser_screenshot
        browser_list
        browser_session_info
        browser_close
      ]
    )
    calls = []
    session_manager_stub = lambda do |**kwargs|
      calls << kwargs.deep_stringify_keys

      case kwargs.fetch(:action)
      when "open"
        { "browser_session_id" => "browser-session-1", "current_url" => kwargs.fetch(:url) }
      when "navigate"
        { "browser_session_id" => kwargs.fetch(:browser_session_id), "current_url" => kwargs.fetch(:url) }
      when "get_content"
        { "browser_session_id" => kwargs.fetch(:browser_session_id), "current_url" => "https://example.com/play", "content" => "2048 ready" }
      when "screenshot"
        { "browser_session_id" => kwargs.fetch(:browser_session_id), "current_url" => "https://example.com/play", "mime_type" => "image/png", "image_base64" => "cG5n" }
      when "list"
        { "entries" => [{ "browser_session_id" => "browser-session-1", "current_url" => "https://example.com/play" }] }
      when "info"
        { "browser_session_id" => kwargs.fetch(:browser_session_id), "current_url" => "https://example.com/play" }
      when "close"
        { "browser_session_id" => kwargs.fetch(:browser_session_id), "closed" => true }
      else
        raise "unexpected browser action #{kwargs.fetch(:action)}"
      end
    end

    with_session_manager_stub(session_manager_stub) do
      opened = executor.call(
        tool_call: {
          "call_id" => "tool-call-browser-1",
          "tool_name" => "browser_open",
          "arguments" => { "url" => "https://example.com/play" },
        }
      )
      content = executor.call(
        tool_call: {
          "call_id" => "tool-call-browser-2",
          "tool_name" => "browser_get_content",
          "arguments" => { "browser_session_id" => "browser-session-1" },
        }
      )
      screenshot = executor.call(
        tool_call: {
          "call_id" => "tool-call-browser-3",
          "tool_name" => "browser_screenshot",
          "arguments" => { "browser_session_id" => "browser-session-1", "full_page" => false },
        }
      )
      listed = executor.call(
        tool_call: {
          "call_id" => "tool-call-browser-4",
          "tool_name" => "browser_list",
          "arguments" => {},
        }
      )
      info = executor.call(
        tool_call: {
          "call_id" => "tool-call-browser-5",
          "tool_name" => "browser_session_info",
          "arguments" => { "browser_session_id" => "browser-session-1" },
        }
      )
      closed = executor.call(
        tool_call: {
          "call_id" => "tool-call-browser-6",
          "tool_name" => "browser_close",
          "arguments" => { "browser_session_id" => "browser-session-1" },
        }
      )

      assert_equal "https://example.com/play", opened.tool_result.fetch("current_url")
      assert_equal "2048 ready", content.tool_result.fetch("content")
      assert_equal "image/png", screenshot.tool_result.fetch("mime_type")
      assert_equal 1, listed.tool_result.fetch("entries").size
      assert_equal "https://example.com/play", info.tool_result.fetch("current_url")
      assert_equal true, closed.tool_result.fetch("closed")
    end

    assert_equal %w[open get_content screenshot list info close], calls.map { |entry| entry.fetch("action") }
    assert_equal "turn-1", calls.first.fetch("agent_task_run_id")
    assert_equal false, calls.third.fetch("full_page")
  end

  test "maps browser validation failures to semantic error payloads" do
    executor = build_executor(allowed_tool_names: ["browser_session_info"])

    error = assert_raises(Fenix::Browser::SessionManager::ValidationError) do
      with_session_manager_stub(->(**) { raise Fenix::Browser::SessionManager::ValidationError, "unknown browser session" }) do
        executor.call(
          tool_call: {
            "call_id" => "tool-call-browser-missing-1",
            "tool_name" => "browser_session_info",
            "arguments" => { "browser_session_id" => "browser-session-missing" },
          }
        )
      end
    end

    assert_equal "validation_error", Fenix::Runtime::ProgramToolExecutor.error_payload_for(error).fetch("code")
  end

  private

  def with_session_manager_stub(callable)
    session_manager_class = Fenix::Browser::SessionManager
    singleton_class = session_manager_class.singleton_class
    original_call = session_manager_class.method(:call)

    singleton_class.send(:define_method, :call, callable)
    yield
  ensure
    singleton_class.send(:define_method, :call) do |*args, **kwargs, &block|
      original_call.call(*args, **kwargs, &block)
    end
  end

  def build_executor(allowed_tool_names:, workspace_root: Dir.pwd)
    Fenix::Runtime::ProgramToolExecutor.new(
      context: {
        "workflow_node_id" => "workflow-node-1",
        "conversation_id" => "conversation-1",
        "turn_id" => "turn-1",
        "agent_context" => { "allowed_tool_names" => allowed_tool_names },
        "workspace_context" => { "workspace_root" => workspace_root },
      }
    )
  end
end
