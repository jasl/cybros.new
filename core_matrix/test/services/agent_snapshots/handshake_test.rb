require "test_helper"

module AgentSnapshots
end

class AgentSnapshots::HandshakeTest < ActiveSupport::TestCase
  test "reuses the authenticated agent snapshot when the runtime contract already matches" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )

    result = AgentSnapshots::Handshake.call(
      agent_snapshot: registration[:agent_snapshot],
      fingerprint: registration[:agent_snapshot].fingerprint,
      protocol_version: "2026-03-25",
      sdk_version: "fenix-0.2.0",
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "capabilities_refresh"),
      tool_catalog: default_tool_catalog("exec_command", "subagent_spawn"),
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      conversation_override_schema_snapshot: { "type" => "object", "properties" => {} },
      default_config_snapshot: {
        "sandbox" => "workspace-read",
        "interactive" => { "selector" => "role:main" },
      }
    )

    assert_equal registration[:agent_snapshot], result.capability_snapshot
    assert_equal 1, result.capability_snapshot.version
    assert_equal "workspace-write", result.capability_snapshot.default_config_snapshot["sandbox"]
    assert_equal "role:researcher", result.capability_snapshot.default_config_snapshot.dig("model_slots", "research", "selector")
    assert_equal "role:summary", result.capability_snapshot.default_config_snapshot.dig("model_slots", "summary", "selector")
    assert_equal default_profile_catalog, result.capability_snapshot.profile_catalog
    assert_equal({}, result.reconciliation_report)
    assert_equal result.capability_snapshot, registration[:agent_snapshot].reload
    assert_equal "2026-03-24", registration[:agent_snapshot].protocol_version
    assert_equal(
      RuntimeCapabilityContract.build(
        execution_runtime: registration[:execution_runtime],
        agent_snapshot: result.capability_snapshot
      ).effective_tool_catalog,
      result.runtime_capability_contract.effective_tool_catalog
    )
  end
end
