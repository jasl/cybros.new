require_relative "../test_helper"
require "verification/active_suite"

class VerificationFreshStartStackContractTest < ActiveSupport::TestCase
  test "fresh start no longer carries dockerized fenix verification branches" do
    script = Verification.repo_root.join("verification", "bin", "fresh_start_stack.sh").read

    refute_includes script, "FENIX_RUNTIME_MODE"
    refute_includes script, "docker run -d \\"
  end

  test "run_with_fresh_start defaults to an active host-side scenario" do
    script = Verification.repo_root.join("verification", "bin", "run_with_fresh_start.sh").read

    assert_includes script, 'TARGET_SCRIPT="${1:-verification/scenarios/e2e/provider_backed_turn_validation.rb}"'
  end

  test "run_with_fresh_start always boots the shared fresh-start stack before executing the target script" do
    script = Verification.repo_root.join("verification", "bin", "run_with_fresh_start.sh").read

    assert_includes script, '"${SCRIPT_DIR}/fresh_start_stack.sh"'
    refute_includes script, 'if [[ "${TARGET_SCRIPT}" =='
  end

  test "verification project owns its own gemfile" do
    gemfile = Verification.repo_root.join("verification", "Gemfile")

    assert gemfile.exist?, "expected verification project to provide a dedicated Gemfile"
  end

  test "multi-fenix load wrappers delegate through the shared load harness with the correct profiles" do
    smoke_script = Verification.repo_root.join("verification", "bin", "multi_fenix_core_matrix_load_smoke.sh").read
    target_script = Verification.repo_root.join("verification", "bin", "multi_fenix_core_matrix_load_target.sh").read
    stress_script = Verification.repo_root.join("verification", "bin", "multi_fenix_core_matrix_load_stress.sh").read

    assert_includes smoke_script, 'MULTI_FENIX_LOAD_PROFILE="${MULTI_FENIX_LOAD_PROFILE:-smoke}"'
    assert_includes target_script, 'MULTI_FENIX_LOAD_PROFILE="${MULTI_FENIX_LOAD_PROFILE:-baseline_1_fenix_4_nexus}"'
    assert_includes stress_script, 'MULTI_FENIX_LOAD_PROFILE="${MULTI_FENIX_LOAD_PROFILE:-stress}"'
    assert_includes smoke_script, "run_multi_fenix_core_matrix_load.sh"
    assert_includes target_script, "run_multi_fenix_core_matrix_load.sh"
    assert_includes stress_script, "run_multi_fenix_core_matrix_load.sh"
  end

  test "shared multi-fenix load harness wires core matrix perf output and starts extra runtime servers" do
    script = Verification.repo_root.join("verification", "bin", "run_multi_fenix_core_matrix_load.sh").read

    assert_includes script, 'CORE_MATRIX_PERF_EVENTS_PATH="${ARTIFACT_DIR}/evidence/core-matrix-events.ndjson"'
    assert_includes script, 'PROVIDER_CATALOG_OVERRIDE_DIR="${RUN_ROOT}/core-matrix-config.d"'
    assert_includes script, 'export PROVIDER_CATALOG_OVERRIDE_DIR'
    assert_includes script, 'require File.join(repo_root, "verification/lib/verification/suites/perf/provider_catalog_override")'
    assert_includes script, "Verification::Perf::ProviderCatalogOverride.write("
    assert_includes script, 'export MULTI_FENIX_LOAD_STACK_ALREADY_RESET="true"'
    assert_includes script, 'bash "${SCRIPT_DIR}/fresh_start_stack.sh"'
    assert_includes script, 'for row in "${SLOT_ROWS[@]}"'
    assert_includes script, "prepare_nexus_slot_home"
    assert_includes script, "bundle\", \"exec\", \"ruby\", \"scripts/manifest_server.rb\""
    assert_includes script, 'wait_for_http_ok "${slot_base_url}/health/ready"'
    assert_includes script, 'bin/rails runner "${REPO_ROOT}/verification/scenarios/perf/multi_fenix_core_matrix_load_validation.rb"'
  end

  test "shared multi-fenix load harness only starts fenix jobs daemons for queued profiles" do
    script = Verification.repo_root.join("verification", "bin", "run_multi_fenix_core_matrix_load.sh").read

    assert_includes script, 'PROFILE_INLINE_CONTROL_WORKER="$('
    assert_includes script, 'require File.join(ENV.fetch("REPO_ROOT"), "verification/lib/verification/suites/perf/profile")'
    assert_includes script, 'START_FENIX_JOBS_DAEMONS="true"'
    assert_includes script, 'if [[ "${PROFILE_INLINE_CONTROL_WORKER}" == "true" ]]; then'
    assert_includes script, 'export FENIX_HOST_START_JOBS_DAEMON="${START_FENIX_JOBS_DAEMONS}"'
    assert_includes script, 'exec("./bin/jobs", "start")'
  end

  test "shared multi-fenix load harness keeps a shared fenix storage root and per-slot nexus storage roots" do
    script = Verification.repo_root.join("verification", "bin", "run_multi_fenix_core_matrix_load.sh").read

    assert_includes script, 'FENIX_STORAGE_ROOT="${FENIX_HOME_ROOT}/storage"'
    assert_includes script, 'NEXUS_STORAGE_ROOT="${slot_storage_root}"'
  end

  test "fresh start can start a fenix jobs daemon for queued host execution" do
    script = Verification.repo_root.join("verification", "bin", "fresh_start_stack.sh").read

    assert_includes script, 'FENIX_HOST_START_JOBS_DAEMON="${FENIX_HOST_START_JOBS_DAEMON:-false}"'
    assert_includes script, 'bin/jobs", "start"'
    assert_includes script, "timed out waiting for fenix-runtime jobs to become ready"
  end

  test "fresh start forwards core matrix perf event env into the server and jobs processes" do
    script = Verification.repo_root.join("verification", "bin", "fresh_start_stack.sh").read

    assert_includes script, 'CORE_MATRIX_PERF_EVENTS_PATH="${CORE_MATRIX_PERF_EVENTS_PATH:-}"'
    assert_includes script, 'CORE_MATRIX_PERF_INSTANCE_LABEL="${CORE_MATRIX_PERF_INSTANCE_LABEL:-}"'
    assert_includes script, "export CORE_MATRIX_PERF_EVENTS_PATH"
    assert_includes script, "export CORE_MATRIX_PERF_INSTANCE_LABEL"
  end

  test "fresh start boots a separate nexus host runtime for split verification scenarios" do
    script = Verification.repo_root.join("verification", "bin", "fresh_start_stack.sh").read

    assert_includes script, 'NEXUS_RUNTIME_BASE_URL="${NEXUS_RUNTIME_BASE_URL:-http://127.0.0.1:3301}"'
    assert_includes script, 'NEXUS_HOME_ROOT="${NEXUS_HOME_ROOT:-${REPO_ROOT}/tmp/verification-nexus-home}"'
    assert_includes script, 'reset_nexus_home_root "${NEXUS_HOME_ROOT}" "${LOG_DIR}/nexus-runtime-db-reset.log"'
    assert_includes script, "start_nexus_manifest_server_daemon \\"
    assert_includes script, 'exec("bundle", "exec", "ruby", "scripts/manifest_server.rb")'
    assert_includes script, 'wait_for_http_ok "${NEXUS_RUNTIME_BASE_URL}/health/ready"'
    assert_includes script, 'wait_for_http_ok "${NEXUS_RUNTIME_BASE_URL}/runtime/manifest"'
    assert_includes script, "nexus_runtime_base_url=${NEXUS_RUNTIME_BASE_URL}"
  end

  test "fresh start waits for the expected core matrix worker topology instead of any solid queue process" do
    script = Verification.repo_root.join("verification", "bin", "fresh_start_stack.sh").read

    assert_includes script, "wait_for_solid_queue_ready()"
    assert_includes script, "start_core_matrix_jobs_daemon()"
    assert_includes script, "expected_queues = %w[llm_dev workflow_default workflow_resume tool_calls]"
    refute_includes script, "SolidQueue::Process.count.positive?"
    assert_includes script, "timed out waiting for core-matrix jobs to become ready"
  end

  test "fresh start reports the actual solid queue supervisor pid instead of the starter shell pid" do
    script = Verification.repo_root.join("verification", "bin", "fresh_start_stack.sh").read

    assert_includes script, 'find_by(kind: "Supervisor(fork)")'
  end

  test "fresh start detaches core matrix jobs through a ruby daemon wrapper instead of shell-backgrounding bin/jobs directly" do
    script = Verification.repo_root.join("verification", "bin", "fresh_start_stack.sh").read

    assert_includes script, "Process.daemon(true, true)"
    assert_includes script, 'exec("./bin/jobs", "start")'
    refute_includes script, "nohup ./bin/jobs start"
  end

  test "fresh start resets rails projects through db:prepare and explicit secondary database schema loads" do
    script = Verification.repo_root.join("verification", "bin", "fresh_start_stack.sh").read

    assert_includes script, '"${RUBY_BIN}" bin/rails db:prepare'
    assert_includes script, "local -a extra_tasks=()"
    assert_includes script, 'if [[ "${#extra_tasks[@]}" -gt 0 ]]; then'
    assert_includes script, 'reset_project_database "core-matrix" "${CORE_MATRIX_ROOT}" "${LOG_DIR}/core-matrix-db-reset.log" "db:schema:load:queue" "db:schema:load:cable"'
    refute_includes script, "rm -f db/schema.rb"
  end

  test "core matrix keeps queue and cable schema snapshots for fresh-start verification resets" do
    assert core_matrix_root.join("db/queue_schema.rb").exist?
    assert core_matrix_root.join("db/cable_schema.rb").exist?
  end

  test "verification readme documents the load wrappers, artifact locations, and bring-your-own flows" do
    readme = Verification.repo_root.join("verification", "README.md").read

    assert_includes readme, "bash verification/bin/run_active_suite.sh"
    assert_includes readme, "bash verification/bin/multi_fenix_core_matrix_load_smoke.sh"
    assert_includes readme, "bash verification/bin/multi_fenix_core_matrix_load_target.sh"
    assert_includes readme, "bash verification/bin/multi_fenix_core_matrix_load_stress.sh"
    assert_includes readme, "verification/artifacts/<artifact-stamp>/review/load-summary.md"
    assert_includes readme, "verification/artifacts/<artifact-stamp>/evidence/aggregated-metrics.json"
    assert_includes readme, "bring_your_own_agent_validation.rb"
    assert_includes readme, "bring_your_own_execution_runtime_validation.rb"
    assert_includes readme, "ACTIVE_VERIFICATION_ENABLE_2048_CAPSTONE=1"
    assert_includes readme, "Shared-Fenix / Multi-Nexus"
  end

  test "active verification suite includes bring-your-own deployment flows" do
    scenarios = Verification::ActiveSuite::ACTIVE_SCENARIOS
    legacy_external_agent_scenario = "verification/scenarios/" + "external_" + "fenix_" + "validation.rb"

    assert_includes scenarios, "verification/scenarios/e2e/bring_your_own_agent_validation.rb"
    assert_includes scenarios, "verification/scenarios/e2e/bring_your_own_execution_runtime_validation.rb"
    refute_includes scenarios, legacy_external_agent_scenario
    refute Verification.repo_root.join(legacy_external_agent_scenario).exist?
  end

  test "bring-your-own flows use agent definition version vocabulary instead of agent snapshot aliases" do
    byo_agent_scenario = Verification.repo_root.join("verification", "scenarios", "e2e", "bring_your_own_agent_validation.rb").read
    byo_runtime_scenario = Verification.repo_root.join("verification", "scenarios", "e2e", "bring_your_own_execution_runtime_validation.rb").read
    byo_integration_test = core_matrix_root.join("test/integration/bring_your_own_agent_pairing_flow_test.rb").read

    refute_includes byo_agent_scenario, "agent_snapshot"
    refute_includes byo_runtime_scenario, "agent_snapshot"
    refute_includes byo_integration_test, "fetch(:agent_snapshot)"
  end

  test "core matrix removes the obsolete execution runtime registration substrate" do
    refute core_matrix_root.join("app/services/execution_runtimes/register.rb").exist?
    refute core_matrix_root.join("app/services/execution_runtimes/record_capabilities.rb").exist?
    refute core_matrix_root.join("test/services/execution_runtimes/record_capabilities_test.rb").exist?

    removed_runtime_constants = [
      "ExecutionRuntimes::" + "Register",
      "ExecutionRuntimes::" + "RecordCapabilities",
    ]
    runtime_sources = Dir.glob(core_matrix_root.join("**/*.rb")).sort.filter_map do |path|
      source = File.read(path)
      next if removed_runtime_constants.none? { |constant_name| source.include?(constant_name) }

      path.delete_prefix("#{core_matrix_root}/")
    end

    assert_empty runtime_sources
  end

  test "core matrix removes the obsolete agent snapshot registration substrate" do
    removed_service_paths = %w[
      app/services/agent_snapshots/register.rb
      app/services/agent_snapshots/handshake.rb
      app/services/agent_snapshots/reconcile_config.rb
      app/services/agent_snapshots/record_heartbeat.rb
      app/services/agent_snapshots/rotate_agent_connection_credential.rb
      app/services/agent_snapshots/revoke_agent_connection_credential.rb
      test/services/agent_snapshots/handshake_test.rb
      test/services/agent_snapshots/reconcile_config_test.rb
    ]

    removed_service_paths.each do |relative_path|
      refute core_matrix_root.join(relative_path).exist?, "expected #{relative_path} to be removed"
    end

    removed_agent_snapshot_constants = [
      "AgentSnapshots::" + "Register",
      "AgentSnapshots::" + "Handshake",
      "AgentSnapshots::" + "ReconcileConfig",
      "AgentSnapshots::" + "RecordHeartbeat",
      "AgentSnapshots::" + "RotateAgentConnectionCredential",
      "AgentSnapshots::" + "RevokeAgentConnectionCredential",
    ]
    lingering_sources = Dir.glob(core_matrix_root.join("**/*.rb")).sort.filter_map do |path|
      source = File.read(path)
      next if removed_agent_snapshot_constants.none? { |constant_name| source.include?(constant_name) }

      path.delete_prefix("#{core_matrix_root}/")
    end

    assert_empty lingering_sources
  end

  test "core matrix removes the obsolete agent enrollment layer" do
    refute core_matrix_root.join("app/models/agent_enrollment.rb").exist?
    refute core_matrix_root.join("app/services/agent_enrollments/issue.rb").exist?
    refute core_matrix_root.join("test/services/agent_enrollments/issue_test.rb").exist?

    removed_agent_enrollment_constants = [
      "AgentEnrollment",
      "AgentEnrollments::" + "Issue",
      "agent_enrollment.issued",
    ]
    lingering_sources = Dir.glob(core_matrix_root.join("**/*.rb")).sort.filter_map do |path|
      source = File.read(path)
      next if removed_agent_enrollment_constants.none? { |constant_name| source.include?(constant_name) }

      path.delete_prefix("#{core_matrix_root}/")
    end

    assert_empty lingering_sources
  end

  private

  def core_matrix_root
    Verification.repo_root.join("core_matrix")
  end
end
