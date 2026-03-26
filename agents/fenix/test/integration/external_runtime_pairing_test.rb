require "test_helper"

class ExternalRuntimePairingTest < ActionDispatch::IntegrationTest
  test "pairing manifest exposes runtime registration metadata for external enrollment" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)

    assert_equal "2026-03-24", body.fetch("protocol_version")
    assert_equal "fenix-0.1.0", body.fetch("sdk_version")
    assert_includes body.fetch("protocol_methods").map { |entry| entry.fetch("method_id") }, "execution_started"
    assert_includes body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "compact_context"
  end
end
