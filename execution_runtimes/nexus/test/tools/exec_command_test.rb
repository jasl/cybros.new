require "test_helper"

class ExecCommandToolTest < Minitest::Test
  def test_exec_command_supports_one_shot_and_attached_contracts
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    host = CybrosNexus::Resources::CommandHost.new(store: store)
    tools = CybrosNexus::Tools::ExecCommand.new(
      command_host: host,
      runtime_owner_id: "task_1",
      workdir: tmp_root
    )

    one_shot = tools.call(
      tool_name: "exec_command",
      arguments: {
        "command_line" => "printf hello",
        "pty" => false,
      },
      resource_ref: {
        "command_run_id" => "cmd_oneshot_123",
      }
    )

    started = tools.call(
      tool_name: "exec_command",
      arguments: {
        "command_line" => "cat",
        "pty" => true,
      },
      resource_ref: {
        "command_run_id" => "cmd_session_123",
      }
    )

    finished = tools.call(
      tool_name: "write_stdin",
      arguments: {
        "command_run_id" => "cmd_session_123",
        "text" => "hello from tool\n",
        "eof" => true,
        "wait_for_exit" => true,
        "timeout_seconds" => 2,
      }
    )

    assert_equal "cmd_oneshot_123", one_shot.fetch("command_run_id")
    assert_equal 0, one_shot.fetch("exit_status")
    assert_equal "hello", one_shot.fetch("stdout_tail")
    assert_equal true, started.fetch("attached")
    assert_equal "cmd_session_123", finished.fetch("command_run_id")
    assert_equal true, finished.fetch("session_closed")
    assert_includes finished.fetch("stdout_tail"), "hello from tool"
  ensure
    host&.shutdown
    store&.close
  end

  def test_command_run_wait_and_terminate_enforce_runtime_ownership
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    host = CybrosNexus::Resources::CommandHost.new(store: store)
    owner_tools = CybrosNexus::Tools::ExecCommand.new(
      command_host: host,
      runtime_owner_id: "task_1",
      workdir: tmp_root
    )
    other_tools = CybrosNexus::Tools::ExecCommand.new(
      command_host: host,
      runtime_owner_id: "task_2",
      workdir: tmp_root
    )

    owner_tools.call(
      tool_name: "exec_command",
      arguments: {
        "command_line" => "sleep 5",
        "pty" => true,
      },
      resource_ref: {
        "command_run_id" => "cmd_session_terminate_123",
      }
    )

    waiting = owner_tools.call(
      tool_name: "command_run_wait",
      arguments: {
        "command_run_id" => "cmd_session_terminate_123",
        "timeout_seconds" => 0,
      }
    )

    error = assert_raises(CybrosNexus::Tools::ExecCommand::ValidationError) do
      other_tools.call(
        tool_name: "write_stdin",
        arguments: {
          "command_run_id" => "cmd_session_terminate_123",
          "text" => "forbidden",
        }
      )
    end

    terminated = owner_tools.call(
      tool_name: "command_run_terminate",
      arguments: {
        "command_run_id" => "cmd_session_terminate_123",
      }
    )

    assert_equal false, waiting.fetch("session_closed")
    assert_equal true, waiting.fetch("timed_out")
    assert_equal true, terminated.fetch("terminated")
    assert_equal true, terminated.fetch("session_closed")
    assert_includes error.message, "not owned"
  ensure
    host&.shutdown
    store&.close
  end
end
