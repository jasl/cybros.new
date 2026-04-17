require_relative "../pure_test_helper"
require "open3"
require "tmpdir"

class VerificationProcessManagerTest < Minitest::Test
  def test_verify_session_clean_fails_while_registered_process_is_still_running
    Dir.mktmpdir("verification-process-manager") do |dir|
      env = manager_env(dir:, session_id: "verify-live")

      _pid, _stderr, status = run_bash(
        env,
        <<~'SH'
          set -euo pipefail
          source "$PROCESS_MANAGER_SCRIPT"
          verification_process_manager_prepare_session
          sleep 30 >/dev/null 2>&1 &
          pid=$!
          verification_process_manager_track_process "sleep-worker" "$pid" ""
          verification_process_manager_verify_session_clean
        SH
      )

      refute status.success?
      run_cleanup(env)
    end
  end

  def test_stop_managed_processes_command_kills_registered_processes
    Dir.mktmpdir("verification-process-manager") do |dir|
      env = manager_env(dir:, session_id: "stop-command")

      pid_text, stderr, status = run_bash(
        env,
        <<~'SH'
          set -euo pipefail
          source "$PROCESS_MANAGER_SCRIPT"
          verification_process_manager_prepare_session
          sleep 30 >/dev/null 2>&1 &
          pid=$!
          verification_process_manager_track_process "sleep-worker" "$pid" ""
          printf '%s\n' "$pid"
        SH
      )

      assert status.success?, stderr
      pid = Integer(pid_text.strip)
      assert process_alive?(pid)

      cleanup_stdout, cleanup_stderr, cleanup_status = Open3.capture3(
        env,
        "bash",
        VerificationPureTestHelper.verification_root.join("bin", "stop_managed_processes.sh").to_s
      )

      assert cleanup_status.success?, [cleanup_stdout, cleanup_stderr].join("\n")
      refute process_alive?(pid)
    end
  end

  private

  def manager_env(dir:, session_id:)
    {
      "PROCESS_MANAGER_SCRIPT" => VerificationPureTestHelper.verification_root.join("bin", "process_manager.sh").to_s,
      "VERIFICATION_PROCESS_REGISTRY_DIR" => dir,
      "VERIFICATION_PROCESS_SESSION_ID" => session_id,
    }
  end

  def run_bash(env, script)
    Open3.capture3(env, "bash", "-lc", script)
  end

  def run_cleanup(env)
    Open3.capture3(
      env,
      "bash",
      VerificationPureTestHelper.verification_root.join("bin", "stop_managed_processes.sh").to_s
    )
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end
end
