require "test_helper"

class AgentApiCapabilitiesControllerTest < ActionDispatch::IntegrationTest
  test "capabilities refresh exposes governed effective tool metadata with public ids" do
    context = build_governed_tool_context!

    get "/agent_api/capabilities", headers: agent_api_headers(context.fetch(:agent_connection_credential))

    assert_response :success

    body = JSON.parse(response.body)
    governed_catalog = body.fetch("governed_effective_tool_catalog")
    shell_entry = governed_catalog.find { |entry| entry.fetch("tool_name") == "exec_command" }
    compact_entry = governed_catalog.find { |entry| entry.fetch("tool_name") == "compact_context" }
    subagent_entry = governed_catalog.find { |entry| entry.fetch("tool_name") == "subagent_spawn" }

    assert shell_entry.fetch("tool_definition_id").match?(/\A[0-9a-f-]{36}\z/)
    assert shell_entry.fetch("tool_implementation_id").match?(/\A[0-9a-f-]{36}\z/)
    assert_equal "whitelist_only", shell_entry.fetch("governance_mode")
    assert_equal "replaceable", compact_entry.fetch("governance_mode")
    assert_equal "reserved", subagent_entry.fetch("governance_mode")
  end

  test "capabilities handshake rejects runtime attempts to use the reserved core_matrix prefix" do
    registration = register_agent_runtime!(
      tool_contract: default_tool_catalog("exec_command")
    )

    post "/agent_api/capabilities",
      params: {
        definition_package: {
          "program_manifest_fingerprint" => registration.fetch(:agent_definition_version).program_manifest_fingerprint,
          "prompt_pack_ref" => registration.fetch(:agent_definition_version).prompt_pack_ref,
          "prompt_pack_fingerprint" => registration.fetch(:agent_definition_version).prompt_pack_fingerprint,
          "protocol_version" => registration.fetch(:agent_definition_version).protocol_version,
          "sdk_version" => registration.fetch(:agent_definition_version).sdk_version,
          "protocol_methods" => default_protocol_methods("agent_health", "capabilities_handshake"),
          "tool_contract" => [
            {
              "tool_name" => "core_matrix__exec_command",
              "tool_kind" => "agent_observation",
              "implementation_source" => "agent",
              "implementation_ref" => "agent/core_matrix__exec_command",
              "input_schema" => { "type" => "object", "properties" => {} },
              "result_schema" => { "type" => "object", "properties" => {} },
              "streaming_support" => false,
              "idempotency_policy" => "best_effort",
            },
          ],
          "profile_policy" => default_profile_policy,
          "canonical_config_schema" => default_canonical_config_schema,
          "conversation_override_schema" => { "type" => "object", "properties" => {} },
          "workspace_agent_settings_schema" => default_workspace_agent_settings_schema,
          "default_workspace_agent_settings" => default_workspace_agent_settings_payload,
          "default_canonical_config" => default_default_canonical_config,
          "reflected_surface" => { "display_name" => "Fenix" },
        },
      },
      headers: agent_api_headers(registration.fetch(:agent_connection_credential)),
      as: :json

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body).fetch("error"), "reserved core_matrix tool names"
  end
end
