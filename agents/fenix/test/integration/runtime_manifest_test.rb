require "test_helper"

class RuntimeManifestTest < ActionDispatch::IntegrationTest
  test "runtime manifest exposes bundled cowork registration metadata" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)
    protocol_method_ids = body.fetch("protocol_methods").map { |entry| entry.fetch("method_id") }
    agent_tool_names = body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }

    assert_equal "fenix", body.fetch("agent_key")
    assert_equal "Fenix", body.fetch("display_name")
    assert_equal "bundled-fenix-release-0.1.0", body.fetch("fingerprint")
    assert_equal "agent-runtime/2026-04-01", body.fetch("protocol_version")
    assert_equal "fenix-0.1.0", body.fetch("sdk_version")
    assert_equal "/runtime/manifest", body.dig("endpoint_metadata", "runtime_manifest_path")
    assert_equal "mailbox-first", body.dig("agent_contract", "transport")
    assert_equal %w[websocket_push poll], body.dig("agent_contract", "delivery")
    assert_equal %w[
      prepare_round
      execute_tool
      supervision_status_refresh
      supervision_guidance
    ], body.dig("agent_contract", "methods")
    assert_includes protocol_method_ids, "capabilities_handshake"
    assert_includes protocol_method_ids, "execution_started"
    assert_includes protocol_method_ids, "process_started"
    assert_includes protocol_method_ids, "process_output"
    assert_includes protocol_method_ids, "process_exited"

    assert_equal "agent", body.dig("agent_plane", "control_plane")
    assert_equal body.fetch("tool_catalog"), body.dig("agent_plane", "tool_catalog")
    assert_equal body.fetch("profile_catalog"), body.dig("agent_plane", "profile_catalog")
    assert_includes agent_tool_names, "compact_context"
    refute_includes agent_tool_names, "exec_command"

    assert_includes body.fetch("profile_catalog").keys, "main"
    assert_includes body.fetch("profile_catalog").keys, "researcher"
    assert_equal true, body.dig("profile_catalog", "researcher", "default_subagent_profile")
    assert_equal "main", body.dig("default_config_snapshot", "interactive", "profile")
    assert_equal true, body.dig("default_config_snapshot", "subagents", "enabled")
    assert_equal 3, body.dig("default_config_snapshot", "subagents", "max_depth")
    assert_equal "boolean", body.dig("conversation_override_schema_snapshot", "properties", "subagents", "properties", "enabled", "type")
  end

  test "runtime manifest exposes idempotency policy for every agent tool" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)

    body.fetch("tool_catalog").each do |entry|
      assert_equal "best_effort", entry.fetch("idempotency_policy"),
        "expected agent tool #{entry.fetch("tool_name")} to declare idempotency_policy"
    end
  end

  test "runtime manifest honors explicit public base url and fingerprint overrides" do
    original_base_url = ENV["FENIX_PUBLIC_BASE_URL"]
    original_fingerprint = ENV["FENIX_RUNTIME_FINGERPRINT"]
    ENV["FENIX_PUBLIC_BASE_URL"] = "http://fenix.example.test:3101"
    ENV["FENIX_RUNTIME_FINGERPRINT"] = "fenix-devbox-a"

    begin
      get "/runtime/manifest"

      assert_response :success

      body = JSON.parse(response.body)

      assert_equal "http://fenix.example.test:3101", body.dig("endpoint_metadata", "base_url")
      assert_equal "fenix-devbox-a", body.fetch("fingerprint")
    ensure
      ENV["FENIX_PUBLIC_BASE_URL"] = original_base_url
      ENV["FENIX_RUNTIME_FINGERPRINT"] = original_fingerprint
    end
  end

  test "runtime manifest falls back to request defaults when override env vars are blank" do
    original_base_url = ENV["FENIX_PUBLIC_BASE_URL"]
    original_fingerprint = ENV["FENIX_RUNTIME_FINGERPRINT"]
    ENV["FENIX_PUBLIC_BASE_URL"] = ""
    ENV["FENIX_RUNTIME_FINGERPRINT"] = ""

    begin
      get "/runtime/manifest"

      assert_response :success

      body = JSON.parse(response.body)

      assert_equal "http://www.example.com", body.dig("endpoint_metadata", "base_url")
      assert_equal "bundled-fenix-release-0.1.0", body.fetch("fingerprint")
    ensure
      ENV["FENIX_PUBLIC_BASE_URL"] = original_base_url
      ENV["FENIX_RUNTIME_FINGERPRINT"] = original_fingerprint
    end
  end
end
