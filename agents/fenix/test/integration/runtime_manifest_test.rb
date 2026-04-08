require "test_helper"

class RuntimeManifestTest < ActionDispatch::IntegrationTest
  test "runtime manifest exposes bundled cowork registration metadata" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)
    protocol_method_ids = body.fetch("protocol_methods").map { |entry| entry.fetch("method_id") }
    program_tool_names = body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    effective_tool_names = body.fetch("effective_tool_catalog").map { |entry| entry.fetch("tool_name") }

    assert_equal "fenix", body.fetch("agent_key")
    assert_equal "Fenix", body.fetch("display_name")
    assert_equal true, body.fetch("includes_executor_program")
    assert_equal "local", body.fetch("executor_kind")
    assert_equal "bundled-fenix-environment", body.fetch("executor_fingerprint")
    assert_equal "agent-program/2026-04-01", body.fetch("protocol_version")
    assert_equal "fenix-0.1.0", body.fetch("sdk_version")
    assert_equal "/runtime/manifest", body.dig("endpoint_metadata", "runtime_manifest_path")
    assert_equal body.fetch("endpoint_metadata"), body.fetch("executor_connection_metadata")
    assert_equal "mailbox-first", body.dig("program_contract", "transport")
    assert_equal %w[websocket_push poll], body.dig("program_contract", "delivery")
    assert_equal %w[
      prepare_round
      execute_program_tool
      supervision_status_refresh
      supervision_guidance
    ], body.dig("program_contract", "methods")
    assert_includes protocol_method_ids, "capabilities_handshake"
    assert_includes protocol_method_ids, "execution_started"

    assert_equal "program", body.dig("program_plane", "control_plane")
    assert_equal "executor", body.dig("executor_plane", "control_plane")
    assert_equal body.fetch("tool_catalog"), body.dig("program_plane", "tool_catalog")
    assert_equal body.fetch("executor_tool_catalog"), body.dig("executor_plane", "tool_catalog")
    assert_equal body.fetch("profile_catalog"), body.dig("program_plane", "profile_catalog")
    assert_includes program_tool_names, "compact_context"
    assert_includes body.fetch("executor_tool_catalog").map { |entry| entry.fetch("tool_name") }, "exec_command"
    assert_includes body.fetch("executor_tool_catalog").map { |entry| entry.fetch("tool_name") }, "write_stdin"
    assert_includes body.fetch("executor_tool_catalog").map { |entry| entry.fetch("tool_name") }, "command_run_list"
    assert_includes body.fetch("executor_tool_catalog").map { |entry| entry.fetch("tool_name") }, "browser_open"
    assert_includes body.fetch("executor_tool_catalog").map { |entry| entry.fetch("tool_name") }, "browser_screenshot"
    assert_includes body.fetch("executor_tool_catalog").map { |entry| entry.fetch("tool_name") }, "browser_session_info"
    refute_includes program_tool_names, "exec_command"
    assert_includes effective_tool_names, "compact_context"
    assert_includes effective_tool_names, "exec_command"
    assert_includes effective_tool_names, "browser_open"
    assert body.fetch("executor_tool_catalog").any? { |entry| entry.fetch("tool_name") == "exec_command" && entry.fetch("operator_group") == "command_run" }
    assert body.fetch("executor_tool_catalog").any? { |entry| entry.fetch("tool_name") == "exec_command" && entry.fetch("supports_streaming_output") == true }
    assert body.fetch("executor_tool_catalog").any? { |entry| entry.fetch("tool_name") == "browser_open" && entry.fetch("operator_group") == "browser_session" }
    assert body.fetch("executor_tool_catalog").any? { |entry| entry.fetch("tool_name") == "browser_screenshot" && entry.fetch("supports_streaming_output") == false }

    assert_includes body.fetch("profile_catalog").keys, "main"
    assert_includes body.fetch("profile_catalog").keys, "researcher"
    assert_equal true, body.dig("profile_catalog", "researcher", "default_subagent_profile")
    assert_equal "main", body.dig("default_config_snapshot", "interactive", "profile")
    assert_equal true, body.dig("default_config_snapshot", "subagents", "enabled")
    assert_equal 3, body.dig("default_config_snapshot", "subagents", "max_depth")
    assert_equal "boolean", body.dig("conversation_override_schema_snapshot", "properties", "subagents", "properties", "enabled", "type")

    foundation = body.dig("executor_capability_payload", "runtime_foundation")
    assert_equal "images/nexus", foundation.fetch("docker_base_project")
    assert_equal "ubuntu-24.04", foundation.fetch("canonical_host_os")
    assert_equal "bin/check-runtime-host", foundation.fetch("bare_metal_validator")
    refute foundation.key?("bootstrap_scripts")
  end

  test "runtime manifest exposes idempotency policy for every executor tool" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)

    body.fetch("executor_tool_catalog").each do |entry|
      assert_equal "best_effort", entry.fetch("idempotency_policy"),
        "expected executor tool #{entry.fetch("tool_name")} to declare idempotency_policy"
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
      assert_equal "http://fenix.example.test:3101", body.dig("executor_connection_metadata", "base_url")
      assert_equal "fenix-devbox-a", body.fetch("executor_fingerprint")
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
      assert_equal "bundled-fenix-environment", body.fetch("executor_fingerprint")
    ensure
      ENV["FENIX_PUBLIC_BASE_URL"] = original_base_url
      ENV["FENIX_RUNTIME_FINGERPRINT"] = original_fingerprint
    end
  end
end
