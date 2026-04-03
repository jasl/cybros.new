require "test_helper"

class RuntimeFoundationTest < ActionDispatch::IntegrationTest
  test "runtime manifest exposes runtime foundation metadata" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)
    foundation = body.fetch("execution_capability_payload").fetch("runtime_foundation")

    assert_equal "ubuntu-24.04", foundation.fetch("base_image")
    assert_includes foundation.fetch("toolchains"), "ruby"
    assert_includes foundation.fetch("toolchains"), "node"
    assert_includes foundation.fetch("toolchains"), "python"
    assert foundation.fetch("bootstrap_scripts").any? { |entry| entry.end_with?("bootstrap-runtime-deps.sh") }
    assert_equal File.read(Rails.root.join(".ruby-version")).strip, foundation.dig("versions", "ruby")
  end
end
