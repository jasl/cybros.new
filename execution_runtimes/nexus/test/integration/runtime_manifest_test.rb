require "test_helper"

class RuntimeManifestTest < ActionDispatch::IntegrationTest
  test "runtime manifest exposes bundled cowork registration metadata" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)
    protocol_method_ids = body.fetch("protocol_methods").map { |entry| entry.fetch("method_id") }
    runtime_tool_names = body.fetch("execution_runtime_tool_catalog").map { |entry| entry.fetch("tool_name") }

    assert_equal "nexus", body.fetch("execution_runtime_key")
    assert_equal "Nexus", body.fetch("display_name")
    assert_equal "local", body.fetch("execution_runtime_kind")
    assert_equal "bundled-nexus-environment", body.fetch("execution_runtime_fingerprint")
    assert_equal "agent-runtime/2026-04-01", body.fetch("protocol_version")
    assert_equal "nexus-0.1.0", body.fetch("sdk_version")
    assert_equal "/runtime/manifest", body.dig("endpoint_metadata", "runtime_manifest_path")
    assert_equal body.fetch("endpoint_metadata"), body.fetch("execution_runtime_connection_metadata")
    assert_equal "mailbox-first", body.dig("execution_runtime_contract", "transport")
    assert_equal %w[websocket_push poll], body.dig("execution_runtime_contract", "delivery")
    assert_equal %w[
      execution_assignment
      resource_close_request
    ], body.dig("execution_runtime_contract", "methods")
    assert_includes protocol_method_ids, "capabilities_handshake"
    assert_includes protocol_method_ids, "execution_started"
    refute_includes protocol_method_ids, "agent_completed"
    refute_includes protocol_method_ids, "agent_failed"
    assert_includes protocol_method_ids, "process_started"
    assert_includes protocol_method_ids, "process_output"
    assert_includes protocol_method_ids, "process_exited"

    assert_equal "execution_runtime", body.dig("execution_runtime_plane", "control_plane")
    assert_equal body.fetch("execution_runtime_tool_catalog"), body.dig("execution_runtime_plane", "tool_catalog")
    assert_equal body.fetch("execution_runtime_capability_payload"), body.dig("execution_runtime_plane", "capability_payload")
    assert_includes runtime_tool_names, "exec_command"
    assert_includes runtime_tool_names, "write_stdin"
    assert_includes runtime_tool_names, "command_run_list"
    assert_includes runtime_tool_names, "browser_open"
    assert_includes runtime_tool_names, "browser_screenshot"
    assert_includes runtime_tool_names, "browser_session_info"
    assert_includes runtime_tool_names, "process_exec"
    assert_includes runtime_tool_names, "process_list"
    assert_includes runtime_tool_names, "process_proxy_info"
    assert_includes runtime_tool_names, "process_read_output"
    assert body.fetch("execution_runtime_tool_catalog").any? { |entry| entry.fetch("tool_name") == "exec_command" && entry.fetch("operator_group") == "command_run" }
    assert body.fetch("execution_runtime_tool_catalog").any? { |entry| entry.fetch("tool_name") == "exec_command" && entry.fetch("supports_streaming_output") == true }
    assert body.fetch("execution_runtime_tool_catalog").any? { |entry| entry.fetch("tool_name") == "browser_open" && entry.fetch("operator_group") == "browser_session" }
    assert body.fetch("execution_runtime_tool_catalog").any? { |entry| entry.fetch("tool_name") == "browser_screenshot" && entry.fetch("supports_streaming_output") == false }
    assert body.fetch("execution_runtime_tool_catalog").any? { |entry| entry.fetch("tool_name") == "process_exec" && entry.fetch("operator_group") == "process_run" }
    assert body.fetch("execution_runtime_tool_catalog").any? { |entry| entry.fetch("tool_name") == "process_read_output" && entry.fetch("resource_identity_kind") == "process_run" }

    foundation = body.dig("execution_runtime_capability_payload", "runtime_foundation")
    assert_equal "images/nexus", foundation.fetch("docker_base_project")
    assert_equal "ubuntu-24.04", foundation.fetch("canonical_host_os")
    assert_equal "bin/check-runtime-host", foundation.fetch("bare_metal_validator")
    refute foundation.key?("bootstrap_scripts")
  end

  test "runtime manifest exposes idempotency policy for every executor tool" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)

    body.fetch("execution_runtime_tool_catalog").each do |entry|
      assert_equal "best_effort", entry.fetch("idempotency_policy"),
        "expected executor tool #{entry.fetch("tool_name")} to declare idempotency_policy"
    end
  end

  test "runtime manifest honors explicit public base url and fingerprint overrides" do
    original_base_url = ENV["NEXUS_PUBLIC_BASE_URL"]
    original_fingerprint = ENV["NEXUS_RUNTIME_FINGERPRINT"]
    ENV["NEXUS_PUBLIC_BASE_URL"] = "http://nexus.example.test:3101"
    ENV["NEXUS_RUNTIME_FINGERPRINT"] = "nexus-devbox-a"

    begin
      get "/runtime/manifest"

      assert_response :success

      body = JSON.parse(response.body)

      assert_equal "http://nexus.example.test:3101", body.dig("endpoint_metadata", "base_url")
      assert_equal "http://nexus.example.test:3101", body.dig("execution_runtime_connection_metadata", "base_url")
      assert_equal "nexus-devbox-a", body.fetch("execution_runtime_fingerprint")
    ensure
      ENV["NEXUS_PUBLIC_BASE_URL"] = original_base_url
      ENV["NEXUS_RUNTIME_FINGERPRINT"] = original_fingerprint
    end
  end

  test "runtime manifest falls back to request defaults when override env vars are blank" do
    original_base_url = ENV["NEXUS_PUBLIC_BASE_URL"]
    original_fingerprint = ENV["NEXUS_RUNTIME_FINGERPRINT"]
    ENV["NEXUS_PUBLIC_BASE_URL"] = ""
    ENV["NEXUS_RUNTIME_FINGERPRINT"] = ""

    begin
      get "/runtime/manifest"

      assert_response :success

      body = JSON.parse(response.body)

      assert_equal "http://www.example.com", body.dig("endpoint_metadata", "base_url")
      assert_equal "bundled-nexus-environment", body.fetch("execution_runtime_fingerprint")
    ensure
      ENV["NEXUS_PUBLIC_BASE_URL"] = original_base_url
      ENV["NEXUS_RUNTIME_FINGERPRINT"] = original_fingerprint
    end
  end
end
