require_relative "../../test_helper"
require "verification/active_suite"
require "verification/suites/proof/capstone_app_api_roundtrip"

class VerificationCapstoneAppApiRoundtripContractTest < ActiveSupport::TestCase
  test "capstone shell wrapper exists as a formal verification entrypoint" do
    script = Verification.repo_root.join("verification", "bin", "fenix_capstone_app_api_roundtrip_validation.sh")

    assert script.exist?, "expected capstone shell wrapper to exist"
  end

  test "capstone scenario exists as a formal verification entrypoint" do
    scenario = Verification.repo_root.join("verification", "scenarios", "proof", "fenix_capstone_app_api_roundtrip_validation.rb")

    assert scenario.exist?, "expected capstone scenario to exist"
  end

  test "active suite exposes the capstone as an optional entrypoint" do
    optional_entry = Verification::ActiveSuite.optional_entrypoints.fetch(
      "verification/bin/fenix_capstone_app_api_roundtrip_validation.sh"
    )

    assert_equal "ACTIVE_VERIFICATION_ENABLE_2048_CAPSTONE", optional_entry.fetch(:env_var)
    assert_includes optional_entry.fetch(:reason), "real provider-backed"
  end

  test "capstone shell wrapper fresh-starts the stack and runs the scenario directly" do
    script = Verification.repo_root.join("verification", "bin", "fenix_capstone_app_api_roundtrip_validation.sh").read

    assert_includes script, 'GENERATED_APP_DIR="${REPO_ROOT}/tmp/fenix/game-2048"'
    assert_includes script, 'source "${SCRIPT_DIR}/process_manager.sh"'
    assert_includes script, 'pkill -f "${GENERATED_APP_DIR}" >/dev/null 2>&1 || true'
    assert_includes script, "verification_process_manager_prepare_session"
    assert_includes script, 'VERIFICATION_PROCESS_MANAGER_PRE_CLEANUP_HOOK="cleanup_capstone_processes"'
    assert_includes script, "trap verification_process_manager_cleanup_current_session_and_verify EXIT"
    assert_includes script, 'bash "${SCRIPT_DIR}/fresh_start_stack.sh"'
    assert_includes script, 'CAPSTONE_HOST_PREVIEW_PORT="${CAPSTONE_HOST_PREVIEW_PORT:-4274}"'
    assert_includes script, 'bin/rails runner "${REPO_ROOT}/verification/scenarios/proof/fenix_capstone_app_api_roundtrip_validation.rb"'
    refute_includes script, "activate_fenix_docker_runtime"
  end

  test "capstone scenario targets the split fenix and nexus topology" do
    scenario = Verification.repo_root.join("verification", "scenarios", "proof", "fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, 'ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")'
    assert_includes scenario, 'ENV.fetch("NEXUS_RUNTIME_BASE_URL", "http://127.0.0.1:3301")'
    assert_includes scenario, "Verification::CliSupport.run!"
    assert_includes scenario, "register_bring_your_own_execution_runtime!"
    assert_includes scenario, "with_fenix_control_worker!"
    assert_includes scenario, "with_nexus_control_worker!"
  end

  test "capstone scenario requires a real provider-backed turn plus runtime and host validation" do
    scenario = Verification.repo_root.join("verification", "scenarios", "proof", "fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, 'ENV.fetch("CAPSTONE_SELECTOR", "role:main")'
    assert_includes scenario, 'ENV.fetch("CAPSTONE_HOST_PREVIEW_PORT", "4274")'
    assert_includes scenario, "Verification::PhaseLogger.build"
    assert_match(/phase_logger\.call\(\s*"turn completed"/m, scenario)
    assert_includes scenario, 'phase_logger.call("host validation started"'
    assert_includes scenario, 'phase_logger.call("conversation export started"'
    assert_includes scenario, 'label: "init-bootstrap"'
    assert_includes scenario, 'label: "init-refresh"'
    assert_includes scenario, 'label: "workspace-create"'
    assert_includes scenario, 'label: "workspace-use"'
    assert_includes scenario, 'label: "agent-attach"'
    assert_includes scenario, 'label: "status"'
    assert_includes scenario, "app_api_admin_create_onboarding_session!"
    assert_includes scenario, "app_api_create_conversation!"
    assert_includes scenario, "wait_for_app_api_turn_terminal!"
    assert_includes scenario, "app_api_conversation_turn_runtime_events!"
    assert_includes scenario, "app_api_debug_export_conversation!"
    assert_includes scenario, "provider_round_*_tool_*"
    assert_includes scenario, "dag_shape_passed"
    assert_includes scenario, "Verification::ConversationRuntimeValidation.build"
    assert_includes scenario, "Verification::HostValidation.run!"
    assert_includes scenario, "app_api_export_conversation!"
    assert_includes scenario, "execution_runtime_id: bring_your_own_runtime_registration.fetch(:execution_runtime).public_id"
    refute_includes scenario, "bootstrap_and_seed!"
    refute_includes scenario, "issue_app_api_session_token!"
    refute_includes scenario, "enable_default_workspace!"
    refute_includes scenario, "wait_for_turn_workflow_terminal!"
    refute_includes scenario, "ConversationDebugExports::BuildPayload.call"
    refute_includes scenario, "OnboardingSessions::Issue.call"
  end

  test "capstone scenario publishes the built artifact into the conversation and re-downloads it through app api" do
    scenario = Verification.repo_root.join("verification", "scenarios", "proof", "fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, "execution_runtime_publish_output_attachment!"
    assert_includes scenario, "Verification::CapstoneTerminalState.inspect!"
    assert_includes scenario, 'publication_role: "primary_deliverable"'
    assert_includes scenario, '"source_kind") == "runtime_generated"'
    assert_includes scenario, "app_api_conversation_attachment_show!"
    assert_includes scenario, "download_url"
    assert_includes scenario, "conversation-export.zip"
    assert_includes scenario, "Digest::SHA256.file"
    assert_includes scenario, "Digest::SHA256.hexdigest"
    refute_includes scenario, "Attachments::CreateArchiveForMessage.call"
  end

  test "capstone prompt forbids foreground shell servers for long-running app startup" do
    prompt = Verification::CapstoneAppApiRoundtrip.prompt(
      generated_app_dir: "/tmp/fenix/game-2048"
    )

    assert_includes prompt, "use the runtime background-process tool"
    assert_includes prompt, "instead of `nohup`, `python -m http.server`"
    assert_includes prompt, "use only non-interactive shell commands with no attached TTY session"
    assert_includes prompt, "do not start a second dev server"
  end

  test "capstone prompt requires a reproducible dependency manifest after config edits" do
    prompt = Verification::CapstoneAppApiRoundtrip.prompt(
      generated_app_dir: "/tmp/fenix/game-2048"
    )

    assert_includes prompt, "if you edit `package.json`, lockfiles, or TypeScript/Vite config"
    assert_includes prompt, "rerun `npm install` before the final `npm run build`"
    assert_includes prompt, "must still pass after that reinstall"
  end
end
