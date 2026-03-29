require "test_helper"

class AgentApiCapabilitiesControllerTest < ActionDispatch::IntegrationTest
  test "capabilities refresh exposes governed effective tool metadata with public ids" do
    context = build_governed_tool_context!

    get "/agent_api/capabilities", headers: agent_api_headers(context.fetch(:machine_credential))

    assert_response :success

    body = JSON.parse(response.body)
    governed_catalog = body.fetch("governed_effective_tool_catalog")
    shell_entry = governed_catalog.find { |entry| entry.fetch("tool_name") == "shell_exec" }
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
      tool_catalog: default_tool_catalog("shell_exec")
    )
    previous_snapshot_id = registration.fetch(:deployment).active_capability_snapshot_id

    post "/agent_api/capabilities",
      params: {
        fingerprint: registration.fetch(:deployment).fingerprint,
        protocol_version: "2026-03-25",
        sdk_version: "fenix-0.2.0",
        protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake"),
        tool_catalog: [
          {
            "tool_name" => "core_matrix__shell_exec",
            "tool_kind" => "agent_observation",
            "implementation_source" => "agent",
            "implementation_ref" => "agent/core_matrix__shell_exec",
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
      headers: agent_api_headers(registration.fetch(:machine_credential)),
      as: :json

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body).fetch("error"), "reserved core_matrix tool names"
    assert_equal previous_snapshot_id, registration.fetch(:deployment).reload.active_capability_snapshot_id
  end
end
