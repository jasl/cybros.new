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
    assert_equal false, body.fetch("environment_plane").fetch("capability_payload").fetch("conversation_attachment_upload")
    assert_equal "FENIX_DEV_PROXY_PORT", body.dig("environment_plane", "capability_payload", "fixed_port_dev_proxy", "external_port_env")
    assert_equal 3310, body.dig("environment_plane", "capability_payload", "fixed_port_dev_proxy", "default_external_port")
    assert_equal "/dev/<process_run_id>", body.dig("environment_plane", "capability_payload", "fixed_port_dev_proxy", "path_prefix_template")
    assert_equal "2026-03-24", body.fetch("protocol_version")
    assert_equal "fenix-0.1.0", body.fetch("sdk_version")
    assert_equal %w[base_url runtime_manifest_path transport], body.fetch("endpoint_metadata").keys.sort
    assert_includes body.fetch("protocol_methods").map { |entry| entry.fetch("method_id") }, "execution_started"
    assert_includes body.fetch("agent_plane").fetch("protocol_methods").map { |entry| entry.fetch("method_id") }, "execution_started"
    assert_equal body.fetch("profile_catalog"), body.fetch("agent_plane").fetch("profile_catalog")
    assert_includes body.fetch("profile_catalog").keys, "main"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "exec_command"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "write_stdin"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "workspace_read"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "workspace_write"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "memory_get"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "memory_search"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "memory_store"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "web_fetch"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "web_search"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "firecrawl_search"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "firecrawl_scrape"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "browser_open"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "browser_navigate"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "browser_get_content"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "browser_screenshot"
    assert_includes body.fetch("environment_tool_catalog").map { |entry| entry.fetch("tool_name") }, "browser_close"
    assert_equal body.fetch("tool_catalog"), body.fetch("agent_plane").fetch("tool_catalog")
    assert_includes body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "compact_context"
    assert_includes body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "exec_command"
    assert_includes body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "workspace_read"
    assert_includes body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "memory_get"
    assert_includes body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "web_fetch"
    assert_includes body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "web_search"
    assert_includes body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "write_stdin"
    assert_includes body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "process_exec"
    assert_includes body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "browser_open"
    assert_includes body.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "browser_get_content"
    assert body.fetch("effective_tool_catalog").any? { |entry| entry.fetch("tool_name") == "compact_context" }
    assert_equal "main", body.dig("default_config_snapshot", "interactive", "profile")
    assert_equal true, body.dig("default_config_snapshot", "subagents", "enabled")
    assert_equal true, body.dig("default_config_snapshot", "subagents", "allow_nested")
    assert_equal 3, body.dig("default_config_snapshot", "subagents", "max_depth")
    assert_nil body.dig("conversation_override_schema_snapshot", "properties", "interactive")
    assert_nil body.dig("conversation_override_schema_snapshot", "properties", "selector")
    assert_equal "boolean", body.dig("conversation_override_schema_snapshot", "properties", "subagents", "properties", "enabled", "type")
  end

  test "pairing manifest honors explicit public base url overrides" do
    original_base_url = ENV["FENIX_PUBLIC_BASE_URL"]
    ENV["FENIX_PUBLIC_BASE_URL"] = "http://fenix.example.test:3101"

    begin
      get "/runtime/manifest"

      assert_response :success

      body = JSON.parse(response.body)

      assert_equal "http://fenix.example.test:3101", body.dig("endpoint_metadata", "base_url")
      assert_equal "http://fenix.example.test:3101", body.dig("environment_connection_metadata", "base_url")
    ensure
      ENV["FENIX_PUBLIC_BASE_URL"] = original_base_url
    end
  end

  test "runtime executions are not exposed as a routable external product endpoint" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/runtime/executions", method: :post)
    end

    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/runtime/executions/runtime-execution-1", method: :get)
    end
  end
end
