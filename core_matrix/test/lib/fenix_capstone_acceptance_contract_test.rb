require "test_helper"
require Rails.root.join("../acceptance/lib/active_suite")
require Rails.root.join("../acceptance/lib/capstone_app_api_roundtrip")

class FenixCapstoneAcceptanceContractTest < ActiveSupport::TestCase
  test "capstone shell wrapper exists as a formal acceptance entrypoint" do
    script = Rails.root.join("../acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh")

    assert script.exist?, "expected capstone shell wrapper to exist"
  end

  test "capstone scenario exists as a formal acceptance entrypoint" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb")

    assert scenario.exist?, "expected capstone scenario to exist"
  end

  test "active suite exposes the capstone as an optional entrypoint" do
    optional_entry = Acceptance::ActiveSuite.optional_entrypoints.fetch(
      "acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh"
    )

    assert_equal "ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE", optional_entry.fetch(:env_var)
    assert_includes optional_entry.fetch(:reason), "real provider-backed"
  end

  test "capstone shell wrapper fresh-starts the stack and runs the scenario directly" do
    script = Rails.root.join("../acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh").read

    assert_includes script, "GENERATED_APP_DIR=\"${REPO_ROOT}/tmp/fenix/game-2048\""
    assert_includes script, "pkill -f \"${GENERATED_APP_DIR}\" >/dev/null 2>&1 || true"
    assert_includes script, "trap cleanup_capstone_processes EXIT"
    assert_includes script, "bash \"${SCRIPT_DIR}/fresh_start_stack.sh\""
    assert_includes script, "CAPSTONE_HOST_PREVIEW_PORT=\"${CAPSTONE_HOST_PREVIEW_PORT:-4274}\""
    assert_includes script, "bin/rails runner \"${REPO_ROOT}/acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb\""
    refute_includes script, "activate_fenix_docker_runtime"
  end

  test "capstone scenario targets the split fenix and nexus topology" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, 'ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")'
    assert_includes scenario, 'ENV.fetch("NEXUS_RUNTIME_BASE_URL", "http://127.0.0.1:3301")'
    assert_includes scenario, "register_bring_your_own_execution_runtime!"
    assert_includes scenario, "with_fenix_control_worker!"
    assert_includes scenario, "with_nexus_control_worker!"
  end

  test "capstone scenario requires a real provider-backed turn plus runtime and host validation" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, 'ENV.fetch("CAPSTONE_SELECTOR", "candidate:openrouter/openai-gpt-5.4")'
    assert_includes scenario, 'ENV.fetch("CAPSTONE_HOST_PREVIEW_PORT", "4274")'
    assert_includes scenario, "issue_app_api_session_token!"
    assert_includes scenario, "app_api_create_conversation!"
    assert_includes scenario, "wait_for_turn_workflow_terminal!"
    assert_includes scenario, "inline_if_queued: false"
    assert_includes scenario, "provider_round_*_tool_*"
    assert_includes scenario, "dag_shape_passed"
    assert_includes scenario, "ConversationDebugExports::BuildPayload.call"
    assert_includes scenario, "ManualAcceptance::ConversationRuntimeValidation.build"
    assert_includes scenario, "Acceptance::HostValidation.run!"
    assert_includes scenario, "app_api_export_conversation!"
    assert_includes scenario, "execution_runtime_id: bring_your_own_runtime_registration.fetch(:execution_runtime).public_id"
  end

  test "capstone prompt forbids foreground shell servers for long-running app startup" do
    prompt = Acceptance::CapstoneAppApiRoundtrip.prompt(
      generated_app_dir: "/tmp/fenix/game-2048"
    )

    assert_includes prompt, "use the runtime background-process tool"
    assert_includes prompt, "instead of `nohup`, `python -m http.server`"
    assert_includes prompt, "use only non-interactive shell commands with no attached TTY session"
    assert_includes prompt, "do not start a second dev server"
  end
end
