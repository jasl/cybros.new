require "test_helper"

class FreshStartStackContractTest < ActiveSupport::TestCase
  test "docker fresh start rebuilds the fenix app image directly from the app dockerfile" do
    script = Rails.root.join("../acceptance/bin/fresh_start_stack.sh").read
    app_build_index = script.index("docker build -t \"${FENIX_DOCKER_IMAGE}\" -f \"${FENIX_ROOT}/Dockerfile\" \"${FENIX_ROOT}\"")
    run_index = script.index("docker run -d \\")

    assert app_build_index.present?, "expected fresh_start_stack.sh to rebuild the fenix app image from the local app Dockerfile"
    assert run_index.present?, "expected fresh_start_stack.sh to run the Docker container"
    assert_operator app_build_index, :<, run_index
    refute_includes script, 'NEXUS_BASE_IMAGE='
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

  test "run_with_fresh_start defaults to an active host-side scenario" do
    script = Rails.root.join("../acceptance/bin/run_with_fresh_start.sh").read

    assert_includes script, 'TARGET_SCRIPT="${1:-acceptance/scenarios/provider_backed_turn_validation.rb}"'
  end

  test "capstone wrapper routes through the shell orchestrator when explicitly requested" do
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

    assert_includes script, 'state.fetch("execution_runtime_connection_credential")'
    assert_includes script, 'execution_runtime_connection_credential="$('
    assert_includes script, 'FENIX_EXECUTION_RUNTIME_CONNECTION_CREDENTIAL="${execution_runtime_connection_credential}"'
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
    assert_includes scenario, "Acceptance::ManualSupport.create_conversation_supervision_session!("
    assert_includes scenario, "Acceptance::ManualSupport.append_conversation_supervision_message!("
    assert_includes scenario, 'response.fetch("machine_status")'
    refute_includes scenario, "conversation_observation"
    refute_includes scenario, "supervisor_status"
    refute_includes scenario, "observation-"
  end

  test "acceptance harness owns its own gemfile" do
    gemfile = Rails.root.join("../acceptance/Gemfile")

    assert gemfile.exist?, "expected acceptance harness to provide a dedicated Gemfile"
  end

  test "multi-fenix load smoke wrapper delegates through the shared load harness with the smoke profile" do
    script = Rails.root.join("../acceptance/bin/multi_fenix_core_matrix_load_smoke.sh").read

    assert_includes script, 'MULTI_FENIX_LOAD_PROFILE="${MULTI_FENIX_LOAD_PROFILE:-smoke}"'
    assert_includes script, "run_multi_fenix_core_matrix_load.sh"
  end

  test "multi-fenix load target wrapper delegates through the shared load harness with the target profile" do
    script = Rails.root.join("../acceptance/bin/multi_fenix_core_matrix_load_target.sh").read

    assert_includes script, 'MULTI_FENIX_LOAD_PROFILE="${MULTI_FENIX_LOAD_PROFILE:-baseline_1_fenix_4_nexus}"'
    assert_includes script, "run_multi_fenix_core_matrix_load.sh"
  end

  test "multi-fenix load stress wrapper delegates through the shared load harness with the stress profile" do
    script = Rails.root.join("../acceptance/bin/multi_fenix_core_matrix_load_stress.sh").read

    assert_includes script, 'MULTI_FENIX_LOAD_PROFILE="${MULTI_FENIX_LOAD_PROFILE:-stress}"'
    assert_includes script, "run_multi_fenix_core_matrix_load.sh"
  end

  test "shared multi-fenix load harness wires core matrix perf output and starts extra runtime servers" do
    script = Rails.root.join("../acceptance/bin/run_multi_fenix_core_matrix_load.sh").read

    assert_includes script, 'CORE_MATRIX_PERF_EVENTS_PATH="${ARTIFACT_DIR}/evidence/core-matrix-events.ndjson"'
    assert_includes script, 'PROVIDER_CATALOG_OVERRIDE_DIR="${RUN_ROOT}/core-matrix-config.d"'
    assert_includes script, "export PROVIDER_CATALOG_OVERRIDE_DIR"
    assert_includes script, 'require File.join(repo_root, "acceptance/lib/perf/provider_catalog_override")'
    assert_includes script, "Acceptance::Perf::ProviderCatalogOverride.write("
    assert_includes script, 'export MULTI_FENIX_LOAD_STACK_ALREADY_RESET="true"'
    assert_includes script, 'bash "${SCRIPT_DIR}/fresh_start_stack.sh"'
    assert_includes script, 'for row in "${SLOT_ROWS[@]}"'
    assert_includes script, 'prepare_nexus_slot_database'
    assert_includes script, "bin/rails db:prepare"
    assert_includes script, 'bin/rails server -d -b 127.0.0.1 -p "${runtime_port}" -P "${pidfile}"'
    assert_includes script, 'bin/rails runner "${REPO_ROOT}/acceptance/scenarios/multi_fenix_core_matrix_load_validation.rb"'
  end

  test "shared multi-fenix load harness only starts fenix jobs daemons for queued profiles" do
    script = Rails.root.join("../acceptance/bin/run_multi_fenix_core_matrix_load.sh").read

    assert_includes script, 'PROFILE_INLINE_CONTROL_WORKER="$('
    assert_includes script, 'require File.join(ENV.fetch("REPO_ROOT"), "acceptance/lib/perf/profile")'
    assert_includes script, 'START_FENIX_JOBS_DAEMONS="true"'
    assert_includes script, 'if [[ "${PROFILE_INLINE_CONTROL_WORKER}" == "true" ]]; then'
    assert_includes script, 'export FENIX_HOST_START_JOBS_DAEMON="${START_FENIX_JOBS_DAEMONS}"'
    assert_includes script, 'if [[ "${START_FENIX_JOBS_DAEMONS}" == "true" ]]; then'
    assert_includes script, 'exec("./bin/jobs", "start")'
  end

  test "shared multi-fenix load harness keeps a shared fenix storage root and per-slot nexus storage roots" do
    script = Rails.root.join("../acceptance/bin/run_multi_fenix_core_matrix_load.sh").read

    assert_includes script, 'FENIX_STORAGE_ROOT="${FENIX_HOME_ROOT}/storage"'
    assert_includes script, 'NEXUS_STORAGE_ROOT="${slot_storage_root}"'
  end

  test "fresh start can start a fenix jobs daemon for queued host execution" do
    script = Rails.root.join("../acceptance/bin/fresh_start_stack.sh").read

    assert_includes script, 'FENIX_HOST_START_JOBS_DAEMON="${FENIX_HOST_START_JOBS_DAEMON:-false}"'
    assert_includes script, 'bin/jobs", "start"'
    assert_includes script, "timed out waiting for fenix-runtime jobs to become ready"
  end

  test "fresh start forwards core matrix perf event env into the server and jobs processes" do
    script = Rails.root.join("../acceptance/bin/fresh_start_stack.sh").read

    assert_includes script, 'CORE_MATRIX_PERF_EVENTS_PATH="${CORE_MATRIX_PERF_EVENTS_PATH:-}"'
    assert_includes script, 'CORE_MATRIX_PERF_INSTANCE_LABEL="${CORE_MATRIX_PERF_INSTANCE_LABEL:-}"'
    assert_includes script, "export CORE_MATRIX_PERF_EVENTS_PATH"
    assert_includes script, "export CORE_MATRIX_PERF_INSTANCE_LABEL"
  end

  test "fresh start boots a separate nexus host runtime for split acceptance scenarios" do
    script = Rails.root.join("../acceptance/bin/fresh_start_stack.sh").read

    assert_includes script, 'NEXUS_ROOT="${NEXUS_PROJECT_ROOT:-${REPO_ROOT}/execution_runtimes/nexus}"'
    assert_includes script, 'NEXUS_RUNTIME_BASE_URL="${NEXUS_RUNTIME_BASE_URL:-http://127.0.0.1:3301}"'
    assert_includes script, 'NEXUS_HOME_ROOT="${NEXUS_HOME_ROOT:-${REPO_ROOT}/tmp/acceptance-nexus-home}"'
    assert_includes script, 'reset_project_database "nexus-runtime" "${NEXUS_ROOT}" "${LOG_DIR}/nexus-runtime-db-reset.log"'
    assert_includes script, 'start_rails_server_daemon "nexus-runtime-server" "${NEXUS_ROOT}" "${NEXUS_RUNTIME_HOST}" "${NEXUS_RUNTIME_PORT}" "${LOG_DIR}/nexus-runtime-server.log"'
    assert_includes script, 'wait_for_http_ok "${NEXUS_RUNTIME_BASE_URL}/runtime/manifest"'
    assert_includes script, 'nexus_runtime_base_url=${NEXUS_RUNTIME_BASE_URL}'
  end

  test "fresh start waits for the expected core matrix worker topology instead of any solid queue process" do
    script = Rails.root.join("../acceptance/bin/fresh_start_stack.sh").read

    assert_includes script, "wait_for_solid_queue_ready()"
    assert_includes script, "start_core_matrix_jobs_daemon()"
    assert_includes script, "expected_queues = %w[llm_dev workflow_default workflow_resume tool_calls]"
    refute_includes script, "SolidQueue::Process.count.positive?"
    assert_includes script, "timed out waiting for core-matrix jobs to become ready"
  end

  test "fresh start reports the actual solid queue supervisor pid instead of the starter shell pid" do
    script = Rails.root.join("../acceptance/bin/fresh_start_stack.sh").read

    assert_includes script, 'find_by(kind: "Supervisor(fork)")'
  end

  test "fresh start detaches core matrix jobs through a ruby daemon wrapper instead of shell-backgrounding bin/jobs directly" do
    script = Rails.root.join("../acceptance/bin/fresh_start_stack.sh").read

    assert_includes script, "Process.daemon(true, true)"
    assert_includes script, 'exec("./bin/jobs", "start")'
    refute_includes script, "nohup ./bin/jobs start"
  end

  test "fresh start resets rails projects through db:prepare and explicit secondary database schema loads" do
    script = Rails.root.join("../acceptance/bin/fresh_start_stack.sh").read

    assert_includes script, '"${RUBY_BIN}" bin/rails db:prepare'
    assert_includes script, "local -a extra_tasks=()"
    assert_includes script, "if [[ \"\${#extra_tasks[@]}\" -gt 0 ]]; then"
    assert_includes script, "reset_project_database \"core-matrix\" \"\${CORE_MATRIX_ROOT}\" \"\${LOG_DIR}/core-matrix-db-reset.log\" \"db:schema:load:queue\" \"db:schema:load:cable\""
    refute_includes script, "rm -f db/schema.rb"
  end

  test "core matrix keeps queue and cable schema snapshots for fresh-start acceptance resets" do
    assert Rails.root.join("db/queue_schema.rb").exist?
    assert Rails.root.join("db/cable_schema.rb").exist?
  end

  test "acceptance readme documents the multi-fenix load wrappers and artifact locations" do
    readme = Rails.root.join("../acceptance/README.md").read

    assert_includes readme, "bash acceptance/bin/multi_fenix_core_matrix_load_smoke.sh"
    assert_includes readme, "bash acceptance/bin/multi_fenix_core_matrix_load_target.sh"
    assert_includes readme, "bash acceptance/bin/multi_fenix_core_matrix_load_stress.sh"
    assert_includes readme, "acceptance/artifacts/<artifact-stamp>/review/load-summary.md"
    assert_includes readme, "acceptance/artifacts/<artifact-stamp>/evidence/aggregated-metrics.json"
    assert_includes readme, "Shared-Fenix / Multi-Nexus"
  end
end
