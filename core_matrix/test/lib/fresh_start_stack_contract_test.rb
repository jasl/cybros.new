require "test_helper"

class FreshStartStackContractTest < ActiveSupport::TestCase
  test "docker fresh start rebuilds the fenix image from the current source tree" do
    script = Rails.root.join("script/manual/acceptance/fresh_start_stack.sh").read
    build_index = script.index("docker build -t \"${FENIX_DOCKER_IMAGE}\" \"${FENIX_ROOT}\"")
    run_index = script.index("docker run -d \\")

    assert build_index.present?, "expected fresh_start_stack.sh to rebuild the Docker image"
    assert run_index.present?, "expected fresh_start_stack.sh to run the Docker container"
    assert_operator build_index, :<, run_index
  end

  test "docker fresh start waits for old container names to disappear before reuse" do
    script = Rails.root.join("script/manual/acceptance/fresh_start_stack.sh").read

    assert_includes script, "wait_for_container_absent \"${FENIX_DOCKER_CONTAINER}\"",
      "expected fresh_start_stack.sh to wait for the runtime container name to clear before docker run"
    assert_includes script, "wait_for_container_absent \"${FENIX_DOCKER_PROXY_CONTAINER}\"",
      "expected fresh_start_stack.sh to wait for the proxy container name to clear before reuse"
  end

  test "docker fresh start clears the persisted fenix volumes before boot" do
    script = Rails.root.join("script/manual/acceptance/fresh_start_stack.sh").read

    assert_includes script, "remove_volume_if_present \"fenix_capstone_storage\""
    assert_includes script, "remove_volume_if_present \"fenix_capstone_proxy_routes\""
  end

  test "capstone wrapper routes through the shell orchestrator" do
    script = Rails.root.join("script/manual/acceptance/run_with_fresh_start.sh").read

    assert_includes script, "exec bash \"${SCRIPT_DIR}/fenix_capstone_app_api_roundtrip_validation.sh\" \"$@\""
  end

  test "fenix runtime activation bootstraps the container and starts bin/runtime-worker" do
    script = Rails.root.join("script/manual/acceptance/activate_fenix_docker_runtime.sh").read

    assert_includes script, "bash scripts/bootstrap-runtime-deps.sh"
    assert_includes script, "docker exec -d -w /rails \"${FENIX_DOCKER_CONTAINER}\" /rails/bin/runtime-worker"
    assert_includes script, "CORE_MATRIX_MACHINE_CREDENTIAL=${FENIX_MACHINE_CREDENTIAL}"
    assert_includes script, "CORE_MATRIX_EXECUTION_MACHINE_CREDENTIAL=${FENIX_EXECUTION_MACHINE_CREDENTIAL}"
  end

  test "capstone orchestrator runs bootstrap before activation and execute" do
    script = Rails.root.join("script/manual/acceptance/fenix_capstone_app_api_roundtrip_validation.sh").read

    assert_match(/CAPSTONE_PHASE=bootstrap .*fenix_capstone_app_api_roundtrip_validation\.rb/m, script)
    assert_match(/activate_fenix_docker_runtime\.sh/m, script)
    assert_match(/CAPSTONE_PHASE=execute .*fenix_capstone_app_api_roundtrip_validation\.rb/m, script)
  end
end
