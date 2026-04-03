require "test_helper"

class AgentApiCapabilitiesControllerTest < ActionDispatch::IntegrationTest
  test "capabilities refresh exposes governed effective tool metadata with public ids" do
    context = build_governed_tool_context!

    get "/program_api/capabilities", headers: program_api_headers(context.fetch(:machine_credential))

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
      tool_catalog: default_tool_catalog("exec_command")
    )

    post "/program_api/capabilities",
      params: {
        fingerprint: registration.fetch(:deployment).fingerprint,
        protocol_version: registration.fetch(:deployment).protocol_version,
        sdk_version: registration.fetch(:deployment).sdk_version,
        protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake"),
        tool_catalog: [
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
        profile_catalog: default_profile_catalog,
        config_schema_snapshot: default_config_schema_snapshot,
        conversation_override_schema_snapshot: { "type" => "object", "properties" => {} },
        default_config_snapshot: default_default_config_snapshot,
      },
      headers: program_api_headers(registration.fetch(:machine_credential)),
      as: :json

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body).fetch("error"), "reserved core_matrix tool names"
  end
end
