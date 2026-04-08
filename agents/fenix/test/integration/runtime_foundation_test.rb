require "test_helper"

class RuntimeFoundationTest < ActionDispatch::IntegrationTest
  test "runtime manifest exposes runtime foundation metadata" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)
    foundation = body.fetch("executor_capability_payload").fetch("runtime_foundation")

    assert_equal "ubuntu-24.04", foundation.fetch("base_image")
    assert_includes foundation.fetch("toolchains"), "ruby"
    assert_includes foundation.fetch("toolchains"), "node"
    assert_includes foundation.fetch("toolchains"), "python"
    assert foundation.fetch("bootstrap_scripts").any? { |entry| entry.end_with?("bootstrap-runtime-deps.sh") }
    assert_equal File.read(Rails.root.join(".ruby-version")).strip, foundation.dig("versions", "ruby")
  end

  test "linux bootstrap script installs the expected execution utilities" do
    script = File.read(Rails.root.join("scripts", "bootstrap-runtime-deps.sh"))

    assert_includes script, "python-is-python3"
    assert_includes script, "lsof"
    assert_includes script, "iproute2"
  end

  test "linux bootstrap script is idempotent across repeated activations" do
    script = File.read(Rails.root.join("scripts", "bootstrap-runtime-deps.sh"))

    assert_includes script, "FENIX_RUNTIME_BOOTSTRAP_STAMP"
    assert_includes script, "sha256sum"
    assert_includes script, "runtime dependencies already satisfied"
    assert_includes script, "write_bootstrap_stamp"
  end
end
