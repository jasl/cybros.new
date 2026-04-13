require "test_helper"

class RuntimeManifestTest < ActionDispatch::IntegrationTest
  test "runtime manifest exposes a normalized definition package" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)
    definition_package = body.fetch("definition_package")
    protocol_method_ids = definition_package.fetch("protocol_methods").map { |entry| entry.fetch("method_id") }
    agent_tool_names = definition_package.fetch("tool_contract").map { |entry| entry.fetch("tool_name") }

    assert_equal "fenix", body.fetch("agent_key")
    assert_equal "Fenix", body.fetch("display_name")
    assert_equal "/runtime/manifest", body.dig("endpoint_metadata", "runtime_manifest_path")
    assert_equal "mailbox-first", body.dig("agent_contract", "transport")
    assert_equal %w[websocket_push poll], body.dig("agent_contract", "delivery")
    assert_equal %w[
      prepare_round
      execute_tool
      supervision_status_refresh
      supervision_guidance
    ], body.dig("agent_contract", "methods")

    assert_equal body.fetch("fingerprint"), definition_package.fetch("program_manifest_fingerprint")
    assert_equal body.fetch("protocol_version"), definition_package.fetch("protocol_version")
    assert_equal body.fetch("sdk_version"), definition_package.fetch("sdk_version")
    assert_equal body.fetch("tool_contract"), definition_package.fetch("tool_contract")
    assert_equal body.fetch("profile_policy"), definition_package.fetch("profile_policy")
    assert_equal body.fetch("canonical_config_schema"), definition_package.fetch("canonical_config_schema")
    assert_equal body.fetch("conversation_override_schema"), definition_package.fetch("conversation_override_schema")
    assert_equal body.fetch("default_canonical_config"), definition_package.fetch("default_canonical_config")
    assert_equal "fenix/default", definition_package.fetch("prompt_pack_ref")
    assert definition_package.fetch("prompt_pack_fingerprint").present?
    assert definition_package.fetch("program_manifest_fingerprint").present?
    assert_equal "Fenix", definition_package.dig("reflected_surface", "display_name")
    assert_includes definition_package.dig("reflected_surface", "example_prompts"), "Summarize the latest changes in this workspace."

    assert_includes protocol_method_ids, "capabilities_handshake"
    assert_includes protocol_method_ids, "agent_completed"
    assert_includes protocol_method_ids, "agent_failed"
    refute_includes protocol_method_ids, "execution_started"
    refute_includes protocol_method_ids, "execution_progress"
    refute_includes protocol_method_ids, "execution_complete"
    refute_includes protocol_method_ids, "execution_fail"
    refute_includes protocol_method_ids, "process_started"
    refute_includes protocol_method_ids, "process_output"
    refute_includes protocol_method_ids, "process_exited"

    assert_equal "agent", body.dig("agent_plane", "control_plane")
    assert_equal body.fetch("tool_contract"), body.dig("agent_plane", "tool_contract")
    assert_equal body.fetch("profile_policy"), body.dig("agent_plane", "profile_policy")
    assert_includes agent_tool_names, "compact_context"
    refute_includes agent_tool_names, "exec_command"

    assert_includes definition_package.fetch("profile_policy").keys, "main"
    assert_includes definition_package.fetch("profile_policy").keys, "researcher"
    assert_equal true, definition_package.dig("profile_policy", "main", "allow_execution_runtime_tools")
    assert_equal true, definition_package.dig("profile_policy", "researcher", "default_subagent_profile")
    assert_equal true, definition_package.dig("profile_policy", "researcher", "allow_execution_runtime_tools")
    assert_equal "main", definition_package.dig("default_canonical_config", "interactive", "default_profile_key")
    assert_equal "role:main", definition_package.dig("default_canonical_config", "role_slots", "main", "selector")
    assert_equal "main", definition_package.dig("default_canonical_config", "role_slots", "summary", "fallback_role_slot")
    assert_equal true, definition_package.dig("canonical_config_schema", "properties", "metadata", "properties", "title_bootstrap", "properties", "enabled", "default")
    assert_equal "runtime_first", definition_package.dig("canonical_config_schema", "properties", "metadata", "properties", "title_bootstrap", "properties", "mode", "default")
    assert_equal true, definition_package.dig("default_canonical_config", "metadata", "title_bootstrap", "enabled")
    assert_equal "runtime_first", definition_package.dig("default_canonical_config", "metadata", "title_bootstrap", "mode")
    assert_equal true, definition_package.dig("default_canonical_config", "subagents", "enabled")
    assert_equal 3, definition_package.dig("default_canonical_config", "subagents", "max_depth")
    assert_equal "boolean", definition_package.dig("conversation_override_schema", "properties", "subagents", "properties", "enabled", "type")
  end

  test "runtime manifest exposes idempotency policy for every agent tool" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)

    body.fetch("definition_package").fetch("tool_contract").each do |entry|
      assert_equal "best_effort", entry.fetch("idempotency_policy"),
        "expected agent tool #{entry.fetch("tool_name")} to declare idempotency_policy"
    end
  end

  test "runtime manifest honors explicit public base url overrides" do
    original_base_url = ENV["FENIX_PUBLIC_BASE_URL"]
    ENV["FENIX_PUBLIC_BASE_URL"] = "http://fenix.example.test:3101"

    begin
      get "/runtime/manifest"

      assert_response :success

      body = JSON.parse(response.body)

      assert_equal "http://fenix.example.test:3101", body.dig("endpoint_metadata", "base_url")
    ensure
      ENV["FENIX_PUBLIC_BASE_URL"] = original_base_url
    end
  end

  test "runtime manifest falls back to request defaults when override env vars are blank" do
    original_base_url = ENV["FENIX_PUBLIC_BASE_URL"]
    ENV["FENIX_PUBLIC_BASE_URL"] = ""

    begin
      get "/runtime/manifest"

      assert_response :success

      body = JSON.parse(response.body)

      assert_equal "http://www.example.com", body.dig("endpoint_metadata", "base_url")
      assert body.fetch("fingerprint").present?
    ensure
      ENV["FENIX_PUBLIC_BASE_URL"] = original_base_url
    end
  end
end
