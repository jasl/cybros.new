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
end
