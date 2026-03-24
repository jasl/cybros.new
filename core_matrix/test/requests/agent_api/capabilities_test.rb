require "test_helper"

class AgentApiCapabilitiesTest < ActionDispatch::IntegrationTest
  test "capabilities refresh returns protocol methods and tool catalog as separate contract sections" do
    registration = register_agent_runtime!

    get "/agent_api/capabilities", headers: agent_api_headers(registration[:machine_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "capabilities_refresh", response_body["method_id"]
    assert_equal ["agent_health", "capabilities_handshake"], response_body["protocol_methods"].map { |entry| entry.fetch("method_id") }
    assert_equal ["kernel_primitive"], response_body["tool_catalog"].map { |entry| entry.fetch("tool_kind") }
  end

  test "capabilities handshake persists a new snapshot and preserves selector-bearing defaults" do
    registration = register_agent_runtime!(
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )

    post "/agent_api/capabilities",
      params: {
        fingerprint: registration[:deployment].fingerprint,
        protocol_version: "2026-03-25",
        sdk_version: "fenix-0.2.0",
        protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "capabilities_refresh"),
        tool_catalog: default_tool_catalog("shell_exec", "subagent_spawn"),
        config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
        conversation_override_schema_snapshot: { type: "object", properties: {} },
        default_config_snapshot: {
          sandbox: "workspace-write",
          interactive: { selector: "role:main" },
        },
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal 2, response_body["agent_capabilities_version"]
    assert_equal "role:researcher", response_body.dig("default_config_snapshot", "model_slots", "research", "selector")
    assert_equal ["agent_health", "capabilities_handshake", "capabilities_refresh"], response_body["protocol_methods"].map { |entry| entry.fetch("method_id") }
    assert_equal 2, registration[:deployment].reload.active_capability_snapshot.version
  end
end
