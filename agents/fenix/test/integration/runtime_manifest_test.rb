require "test_helper"

class RuntimeManifestTest < ActionDispatch::IntegrationTest
  test "runtime manifest exposes a normalized definition package" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)
    definition_package = body.fetch("definition_package")
    protocol_method_ids = definition_package.fetch("protocol_methods").map { |entry| entry.fetch("method_id") }
    feature_keys = definition_package.fetch("feature_contract").map { |entry| entry.fetch("feature_key") }
    agent_tool_names = definition_package.fetch("tool_contract").map { |entry| entry.fetch("tool_name") }
    request_preparation_contract = definition_package.fetch("request_preparation_contract")

    assert_equal "fenix", body.fetch("agent_key")
    assert_equal "Fenix", body.fetch("display_name")
    assert_equal "/runtime/manifest", body.dig("endpoint_metadata", "runtime_manifest_path")
    assert_equal "mailbox-first", body.dig("agent_contract", "transport")
    assert_equal %w[websocket_push poll], body.dig("agent_contract", "delivery")
    assert_equal %w[
      prepare_round
      consult_prompt_compaction
      execute_prompt_compaction
      execute_tool
      execute_feature
      supervision_status_refresh
      supervision_guidance
    ], body.dig("agent_contract", "methods")

    assert_equal body.fetch("fingerprint"), definition_package.fetch("program_manifest_fingerprint")
    assert_equal body.fetch("protocol_version"), definition_package.fetch("protocol_version")
    assert_equal body.fetch("sdk_version"), definition_package.fetch("sdk_version")
    assert_equal body.fetch("feature_contract"), definition_package.fetch("feature_contract")
    assert_equal body.fetch("request_preparation_contract"), definition_package.fetch("request_preparation_contract")
    assert_equal body.fetch("tool_contract"), definition_package.fetch("tool_contract")
    assert_equal body.fetch("canonical_config_schema"), definition_package.fetch("canonical_config_schema")
    assert_equal body.fetch("conversation_override_schema"), definition_package.fetch("conversation_override_schema")
    assert_equal body.fetch("workspace_agent_settings_schema"), definition_package.fetch("workspace_agent_settings_schema")
    assert_equal body.fetch("default_workspace_agent_settings"), definition_package.fetch("default_workspace_agent_settings")
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
    assert_equal body.fetch("feature_contract"), body.dig("agent_plane", "feature_contract")
    assert_equal body.fetch("request_preparation_contract"), body.dig("agent_plane", "request_preparation_contract")
    assert_equal body.fetch("tool_contract"), body.dig("agent_plane", "tool_contract")
    assert_equal body.fetch("workspace_agent_settings_schema"), body.dig("agent_plane", "workspace_agent_settings_schema")
    assert_equal body.fetch("default_workspace_agent_settings"), body.dig("agent_plane", "default_workspace_agent_settings")
    assert_includes feature_keys, "title_bootstrap"
    assert_equal "direct_optional", request_preparation_contract.dig("prompt_compaction", "consultation_mode")
    assert_equal "supported", request_preparation_contract.dig("prompt_compaction", "workflow_execution")
    assert_includes agent_tool_names, "compact_context"
    refute_includes agent_tool_names, "exec_command"

    assert_equal "object", definition_package.dig("workspace_agent_settings_schema", "type")
    assert_equal "pragmatic", definition_package.dig("default_workspace_agent_settings", "agent", "interactive", "profile_key")
    assert_equal "researcher", definition_package.dig("default_workspace_agent_settings", "agent", "subagents", "default_profile_key")
    assert_equal %w[researcher developer tester], definition_package.dig("default_workspace_agent_settings", "agent", "subagents", "enabled_profile_keys")
    assert_equal "role:main", definition_package.dig("default_workspace_agent_settings", "core_matrix", "interactive", "model_selector")
    assert_equal "role:main", definition_package.dig("default_workspace_agent_settings", "core_matrix", "subagents", "default_model_selector")
    assert_nil definition_package.dig("default_workspace_agent_settings", "core_matrix", "subagents", "label_model_selectors")
    assert_equal "default", definition_package.dig("default_canonical_config", "interactive", "default_profile_key")
    assert_equal "role:main", definition_package.dig("default_canonical_config", "role_slots", "main", "selector")
    assert_equal "main", definition_package.dig("default_canonical_config", "role_slots", "summary", "fallback_role_slot")
    assert definition_package.dig("default_canonical_config", "profile_runtime_overrides", "default").present?
    assert definition_package.dig("reflected_surface", "profiles", "friendly").present?
    assert definition_package.dig("reflected_surface", "profiles", "pragmatic").present?
    refute definition_package.dig("reflected_surface", "profiles", "default").present?
    assert_equal "embedded_only", definition_package.dig("canonical_config_schema", "properties", "features", "properties", "title_bootstrap", "properties", "strategy", "default")
    assert_equal "runtime_first", definition_package.dig("canonical_config_schema", "properties", "features", "properties", "prompt_compaction", "properties", "strategy", "default")
    assert_equal "embedded_only", definition_package.dig("default_canonical_config", "features", "title_bootstrap", "strategy")
    assert_equal "runtime_first", definition_package.dig("default_canonical_config", "features", "prompt_compaction", "strategy")
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
