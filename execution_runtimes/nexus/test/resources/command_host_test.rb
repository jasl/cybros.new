require "test_helper"

class CommandHostTest < Minitest::Test
  def test_start_runs_one_shot_command_and_returns_output_summary
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    host = CybrosNexus::Resources::CommandHost.new(store: store)

    result = host.start(
      command_run_id: "cmd_123",
      runtime_owner_id: "task_1",
      command_line: "printf hello",
      pty: false,
      workdir: tmp_root
    )

    assert_equal "cmd_123", result.fetch("command_run_id")
    assert_equal 0, result.fetch("exit_status")
    assert_equal "hello", result.fetch("stdout_tail")
    assert_equal "", result.fetch("stderr_tail")
    assert_equal ["CommandRun", "stopped"], store.database.get_first_row(
      "SELECT resource_type, state FROM resource_handles WHERE resource_id = ?",
      ["cmd_123"]
    )
  ensure
    host&.shutdown
    store&.close
  end

  def test_pty_sessions_stay_addressable_by_the_same_public_id
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    host = CybrosNexus::Resources::CommandHost.new(store: store)

    started = host.start(
      command_run_id: "cmd_pty_123",
      runtime_owner_id: "task_1",
      command_line: "cat",
      pty: true,
      workdir: tmp_root
    )

    finished = host.write_stdin(
      command_run_id: "cmd_pty_123",
      runtime_owner_id: "task_1",
      text: "hello from pty\n",
      eof: true,
      wait_for_exit: true,
      timeout_seconds: 2
    )

    assert_equal "cmd_pty_123", started.fetch("command_run_id")
    assert_equal true, started.fetch("attached")
    assert_equal "cmd_pty_123", finished.fetch("command_run_id")
    assert_equal true, finished.fetch("session_closed")
    assert_equal 0, finished.fetch("exit_status")
    assert_includes finished.fetch("stdout_tail"), "hello from pty"
  ensure
    host&.shutdown
    store&.close
  end
end
