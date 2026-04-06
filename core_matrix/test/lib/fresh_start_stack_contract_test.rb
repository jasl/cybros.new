require "test_helper"

class FreshStartStackContractTest < ActiveSupport::TestCase
  test "docker fresh start rebuilds the fenix image from the current source tree" do
    script = Rails.root.join("../acceptance/bin/fresh_start_stack.sh").read
    build_index = script.index("docker build -t \"${FENIX_DOCKER_IMAGE}\" \"${FENIX_ROOT}\"")
    run_index = script.index("docker run -d \\")

    assert build_index.present?, "expected fresh_start_stack.sh to rebuild the Docker image"
    assert run_index.present?, "expected fresh_start_stack.sh to run the Docker container"
    assert_operator build_index, :<, run_index
  end

  test "docker fresh start waits for old container names to disappear before reuse" do
    script = Rails.root.join("../acceptance/bin/fresh_start_stack.sh").read

    assert_includes script, "wait_for_container_absent \"${FENIX_DOCKER_CONTAINER}\"",
      "expected fresh_start_stack.sh to wait for the runtime container name to clear before docker run"
    assert_includes script, "wait_for_container_absent \"${FENIX_DOCKER_PROXY_CONTAINER}\"",
      "expected fresh_start_stack.sh to wait for the proxy container name to clear before reuse"
  end

  test "docker fresh start clears the persisted fenix volumes before boot" do
    script = Rails.root.join("../acceptance/bin/fresh_start_stack.sh").read

    assert_includes script, "remove_volume_if_present \"fenix_capstone_storage\""
    assert_includes script, "remove_volume_if_present \"fenix_capstone_proxy_routes\""
  end

  test "capstone wrapper routes through the shell orchestrator" do
    script = Rails.root.join("../acceptance/bin/run_with_fresh_start.sh").read

    assert_includes script, "exec bash \"${SCRIPT_DIR}/fenix_capstone_app_api_roundtrip_validation.sh\" \"$@\""
  end

  test "fenix runtime activation bootstraps the container and starts bin/runtime-worker" do
    script = Rails.root.join("../acceptance/bin/activate_fenix_docker_runtime.sh").read

    assert_includes script, "bash scripts/bootstrap-runtime-deps.sh"
    assert_includes script, "docker exec -d -w /rails \"${FENIX_DOCKER_CONTAINER}\" /rails/bin/runtime-worker"
    assert_includes script, "CORE_MATRIX_MACHINE_CREDENTIAL=${FENIX_MACHINE_CREDENTIAL}"
    assert_includes script, "CORE_MATRIX_EXECUTION_MACHINE_CREDENTIAL=${FENIX_EXECUTION_MACHINE_CREDENTIAL}"
  end

  test "capstone orchestrator runs bootstrap before activation and execute" do
    script = Rails.root.join("../acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh").read

    assert_match(/CAPSTONE_PHASE=bootstrap .*acceptance\/scenarios\/fenix_capstone_app_api_roundtrip_validation\.rb/m, script)
    assert_match(/activate_fenix_docker_runtime\.sh/m, script)
    assert_match(/CAPSTONE_PHASE=execute .*acceptance\/scenarios\/fenix_capstone_app_api_roundtrip_validation\.rb/m, script)
    assert_includes script, "ARTIFACT_DIR=\"${REPO_ROOT}/acceptance/artifacts/${ARTIFACT_STAMP}\""
  end

  test "capstone orchestrator derives a readable timestamped artifact stamp once and exports it" do
    script = Rails.root.join("../acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh").read

    assert_includes script, "DEFAULT_ARTIFACT_STAMP=\"$(date '+%Y-%m-%d-%H%M%S')-core-matrix-loop-fenix-2048-final\""
    assert_includes script, "ARTIFACT_STAMP=\"${CAPSTONE_ARTIFACT_STAMP:-${DEFAULT_ARTIFACT_STAMP}}\""
    assert_includes script, "export CAPSTONE_ARTIFACT_STAMP=\"${ARTIFACT_STAMP}\""
  end

  test "capstone scenario derives its artifact stamp from the environment before using a timestamped fallback" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, 'ENV.fetch("CAPSTONE_ARTIFACT_STAMP")'
    assert_includes scenario, 'Time.current.strftime("%Y-%m-%d-%H%M%S")'
    refute_includes scenario, 'ARTIFACT_STAMP = "2026-04-03-core-matrix-loop-fenix-2048-final".freeze'
  end

  test "capstone scenario writes human-readable supervision markdown artifacts" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read
    helper = Rails.root.join("../acceptance/lib/conversation_artifacts.rb").read

    assert_includes scenario, "Acceptance::ConversationArtifacts.write_supervision_artifacts!"
    assert_includes helper, "def supervision_sidechat_markdown"
    assert_includes helper, "def supervision_status_markdown"
    assert_includes helper, "def supervision_feed_markdown"
    assert_includes helper, '"supervision-sidechat.md"'
    assert_includes helper, '"supervision-status.md"'
    assert_includes helper, '"supervision-feed.md"'
  end

  test "supervision sidechat artifact keeps human sidechat separate from proof and debug refs" do
    helper = Rails.root.join("../acceptance/lib/conversation_artifacts.rb").read

    assert_includes helper, "append_supervision_grounding_lines"
    refute_includes helper, 'append_supervision_proof_ref_lines(lines, human_sidechat.fetch("proof_refs"))'
  end

  test "capstone scenario uses supervision naming and helper entrypoints" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, 'SUPERVISION_PROMPT = "Please tell me what you are doing right now and what changed most recently."'
    assert_includes scenario, "ManualAcceptanceSupport.create_conversation_supervision_session!("
    assert_includes scenario, "ManualAcceptanceSupport.append_conversation_supervision_message!("
    assert_includes scenario, 'response.fetch("machine_status")'
    refute_includes scenario, "conversation_observation"
    refute_includes scenario, "supervisor_status"
    refute_includes scenario, "observation-"
  end

  test "acceptance harness owns its own gemfile" do
    gemfile = Rails.root.join("../acceptance/Gemfile")

    assert gemfile.exist?, "expected acceptance harness to provide a dedicated Gemfile"
  end
end
