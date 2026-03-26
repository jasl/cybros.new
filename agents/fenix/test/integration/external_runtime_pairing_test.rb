require "test_helper"

class ExternalRuntimePairingTest < ActionDispatch::IntegrationTest
  test "pairing manifest exposes runtime registration metadata for external enrollment" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)

    assert_equal true, body.fetch("includes_execution_environment")
    assert_equal "local", body.fetch("environment_kind")
    assert body.fetch("environment_fingerprint").present?
    assert_equal false, body.fetch("environment_plane").fetch("capability_payload").fetch("conversation_attachment_upload")
    assert_equal "2026-03-24", body.fetch("protocol_version")
    assert_equal "fenix-0.1.0", body.fetch("sdk_version")
    assert_includes body.fetch("protocol_methods").map { |entry| entry.fetch("method_id") }, "execution_started"
    assert_includes body.fetch("agent_plane").fetch("protocol_methods").map { |entry| entry.fetch("method_id") }, "execution_started"
    assert_equal body.fetch("tool_catalog"), body.fetch("agent_plane").fetch("tool_catalog")
    assert_includes body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "compact_context"
    assert body.fetch("effective_tool_catalog").any? { |entry| entry.fetch("tool_name") == "compact_context" }
  end
end
