require_relative "../test_helper"

class VerificationProcessManagerContractTest < ActiveSupport::TestCase
  test "fresh start stack auto-sweeps previously managed verification processes before booting" do
    script = Verification.repo_root.join("verification", "bin", "fresh_start_stack.sh").read

    assert_includes script, 'source "${SCRIPT_DIR}/process_manager.sh"'
    assert_includes script, "verification_process_manager_auto_sweep"
  end

  test "run_with_fresh_start prepares a managed session and verifies cleanup on exit" do
    script = Verification.repo_root.join("verification", "bin", "run_with_fresh_start.sh").read

    assert_includes script, 'source "${SCRIPT_DIR}/process_manager.sh"'
    assert_includes script, "verification_process_manager_prepare_session"
    assert_includes script, "trap verification_process_manager_cleanup_current_session_and_verify EXIT"
  end

  test "load and capstone wrappers both use the shared process manager" do
    load_script = Verification.repo_root.join("verification", "bin", "run_multi_fenix_core_matrix_load.sh").read
    capstone_script = Verification.repo_root.join("verification", "bin", "fenix_capstone_app_api_roundtrip_validation.sh").read

    assert_includes load_script, 'source "${SCRIPT_DIR}/process_manager.sh"'
    assert_includes load_script, "verification_process_manager_prepare_session"
    assert_includes load_script, "verification_process_manager_cleanup_current_session_and_verify"
    assert_includes capstone_script, 'source "${SCRIPT_DIR}/process_manager.sh"'
    assert_includes capstone_script, "verification_process_manager_prepare_session"
    assert_includes capstone_script, "verification_process_manager_cleanup_current_session_and_verify"
  end

  test "verification bin provides an explicit managed-process cleanup command" do
    cleanup_script = Verification.repo_root.join("verification", "bin", "stop_managed_processes.sh")

    assert cleanup_script.exist?, "expected explicit managed-process cleanup command"
  end

  test "active suite installs managed-process cleanup on exit" do
    script = Verification.repo_root.join("verification", "bin", "run_active_suite.sh").read

    assert_includes script, "cleanup_active_suite_managed_processes_on_exit()"
    assert_includes script, 'bash "${SCRIPT_DIR}/stop_managed_processes.sh" || status=1'
    assert_includes script, "trap cleanup_active_suite_managed_processes_on_exit EXIT"
  end
end
