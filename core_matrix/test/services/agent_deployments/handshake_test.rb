require "test_helper"

module AgentDeployments
end

class AgentDeployments::HandshakeTest < ActiveSupport::TestCase
  test "persists a new capability snapshot and reconciles selector-bearing defaults" do
    registration = register_agent_runtime!(
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )

    result = AgentDeployments::Handshake.call(
      deployment: registration[:deployment],
      fingerprint: registration[:deployment].fingerprint,
      protocol_version: "2026-03-25",
      sdk_version: "fenix-0.2.0",
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "capabilities_refresh"),
      tool_catalog: default_tool_catalog("shell_exec", "subagent_spawn"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      conversation_override_schema_snapshot: { "type" => "object", "properties" => {} },
      default_config_snapshot: {
        "sandbox" => "workspace-read",
        "interactive" => { "selector" => "role:main" },
      }
    )

    assert_equal 2, result.capability_snapshot.version
    assert_equal "workspace-read", result.capability_snapshot.default_config_snapshot["sandbox"]
    assert_equal "role:researcher", result.capability_snapshot.default_config_snapshot.dig("model_slots", "research", "selector")
    assert_equal ["model_slots"], result.reconciliation_report["retained_keys"]
    assert_equal result.capability_snapshot, registration[:deployment].reload.active_capability_snapshot
    assert_equal "2026-03-25", registration[:deployment].protocol_version
  end
end
