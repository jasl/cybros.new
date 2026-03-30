require "test_helper"

class ExternalRuntimePairingTest < ActionDispatch::IntegrationTest
  test "pairing manifest exposes runtime registration metadata for external enrollment" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)

    assert_equal true, body.fetch("includes_execution_environment")
    assert_equal "local", body.fetch("environment_kind")
    assert body.fetch("environment_fingerprint").present?
    assert_equal "/runtime/manifest", body.dig("endpoint_metadata", "runtime_manifest_path")
    assert_nil body.dig("endpoint_metadata", "runtime_execution_path")
    assert_nil body.dig("environment_connection_metadata", "runtime_execution_path")
    assert_equal false, body.fetch("environment_plane").fetch("capability_payload").fetch("conversation_attachment_upload")
    assert_equal "2026-03-24", body.fetch("protocol_version")
    assert_equal "fenix-0.1.0", body.fetch("sdk_version")
    assert_equal %w[base_url runtime_manifest_path transport], body.fetch("endpoint_metadata").keys.sort
    assert_includes body.fetch("protocol_methods").map { |entry| entry.fetch("method_id") }, "execution_started"
    assert_includes body.fetch("agent_plane").fetch("protocol_methods").map { |entry| entry.fetch("method_id") }, "execution_started"
    assert_equal body.fetch("profile_catalog"), body.fetch("agent_plane").fetch("profile_catalog")
    assert_includes body.fetch("profile_catalog").keys, "main"
    assert_equal body.fetch("tool_catalog"), body.fetch("agent_plane").fetch("tool_catalog")
    assert_includes body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "compact_context"
    assert body.fetch("effective_tool_catalog").any? { |entry| entry.fetch("tool_name") == "compact_context" }
    assert_equal "main", body.dig("default_config_snapshot", "interactive", "profile")
    assert_equal true, body.dig("default_config_snapshot", "subagents", "enabled")
    assert_equal true, body.dig("default_config_snapshot", "subagents", "allow_nested")
    assert_equal 3, body.dig("default_config_snapshot", "subagents", "max_depth")
    assert_nil body.dig("conversation_override_schema_snapshot", "properties", "interactive")
    assert_nil body.dig("conversation_override_schema_snapshot", "properties", "selector")
    assert_equal "boolean", body.dig("conversation_override_schema_snapshot", "properties", "subagents", "properties", "enabled", "type")
  end
end
