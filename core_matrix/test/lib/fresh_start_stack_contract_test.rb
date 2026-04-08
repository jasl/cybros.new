require "test_helper"

class FreshStartStackContractTest < ActiveSupport::TestCase
  test "docker fresh start rebuilds nexus before the fenix app image" do
    script = Rails.root.join("../acceptance/bin/fresh_start_stack.sh").read
    base_build_index = script.index("docker build -t \"${NEXUS_DOCKER_IMAGE}\" -f \"${NEXUS_ROOT}/Dockerfile\" \"${REPO_ROOT}\"")
    app_build_index = script.index("docker build --build-arg \"NEXUS_BASE_IMAGE=${NEXUS_DOCKER_IMAGE}\" -t \"${FENIX_DOCKER_IMAGE}\" -f \"${FENIX_ROOT}/Dockerfile\" \"${FENIX_ROOT}\"")
    run_index = script.index("docker run -d \\")

    assert base_build_index.present?, "expected fresh_start_stack.sh to build the shared nexus base image"
    assert app_build_index.present?, "expected fresh_start_stack.sh to rebuild the fenix app image against the shared nexus base image"
    assert run_index.present?, "expected fresh_start_stack.sh to run the Docker container"
    assert_operator base_build_index, :<, app_build_index
    assert_operator app_build_index, :<, run_index
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

  test "generic docker runtime activation starts bin/runtime-worker without legacy bootstrap expectations" do
    script = Rails.root.join("../acceptance/bin/activate_agent_docker_runtime.sh").read

    assert_includes script, "docker exec -d -w /rails \"${AGENT_DOCKER_CONTAINER}\" /rails/bin/runtime-worker"
    refute_includes script, "bootstrap-runtime-deps.sh"
  end

  test "fenix runtime activation is a thin wrapper around the generic docker activator" do
    script = Rails.root.join("../acceptance/bin/activate_fenix_docker_runtime.sh").read

    assert_includes script, "activate_agent_docker_runtime.sh"
    assert_includes script, "AGENT_DOCKER_IMAGE"
    assert_includes script, "AGENT_DOCKER_CONTAINER"
    assert_includes script, "exec bash \"${SCRIPT_DIR}/activate_agent_docker_runtime.sh\""
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

  test "capstone orchestrator reads executor bootstrap credentials from state while preserving runtime env wiring" do
    script = Rails.root.join("../acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh").read

    assert_includes script, 'state.fetch("executor_machine_credential")'
    assert_includes script, 'executor_machine_credential="$('
    assert_includes script, 'FENIX_EXECUTION_MACHINE_CREDENTIAL="${executor_machine_credential}"'
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
    assert_includes helper, '"supervision-eval-bundle.json"'
  end

  test "supervision sidechat artifact keeps human sidechat separate from proof and debug refs" do
    helper = Rails.root.join("../acceptance/lib/conversation_artifacts.rb").read

    assert_includes helper, "append_supervision_grounding_lines"
    refute_includes helper, 'append_supervision_proof_ref_lines(lines, human_sidechat.fetch("proof_refs"))'
  end

  test "offline supervision replay shell entry point delegates through rails runner" do
    script = Rails.root.join("../acceptance/bin/replay_supervision_eval.sh").read

    assert_includes script, "supervision_eval_replay"
    assert_includes script, "bin/rails runner"
    assert_includes script, "ARGV.fetch(0)"
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
