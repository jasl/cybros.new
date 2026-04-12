require "test_helper"

class AgentDefinitionVersions::HandshakeTest < ActiveSupport::TestCase
  test "reuses the authenticated agent definition version when the normalized package already matches" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )

    result = AgentDefinitionVersions::Handshake.call(
      agent_connection: registration[:agent_connection],
      execution_runtime: registration[:execution_runtime],
      definition_package: {
        "program_manifest_fingerprint" => registration[:agent_definition_version].program_manifest_fingerprint,
        "prompt_pack_ref" => registration[:agent_definition_version].prompt_pack_ref,
        "prompt_pack_fingerprint" => registration[:agent_definition_version].prompt_pack_fingerprint,
        "protocol_version" => registration[:agent_definition_version].protocol_version,
        "sdk_version" => registration[:agent_definition_version].sdk_version,
        "protocol_methods" => registration[:agent_definition_version].protocol_methods,
        "tool_contract" => registration[:agent_definition_version].tool_contract,
        "profile_policy" => registration[:agent_definition_version].profile_policy,
        "canonical_config_schema" => registration[:agent_definition_version].canonical_config_schema,
        "conversation_override_schema" => registration[:agent_definition_version].conversation_override_schema,
        "default_canonical_config" => registration[:agent_definition_version].default_canonical_config,
        "reflected_surface" => registration[:agent_definition_version].reflected_surface,
      }
    )

    assert_equal registration[:agent_definition_version], result.agent_definition_version
    assert_equal registration[:agent_definition_version], result.agent_definition_version
    assert_equal 1, result.agent_definition_version.version
    assert_equal "workspace-write", result.agent_definition_version.default_config_snapshot["sandbox"]
    assert_equal "role:researcher", result.agent_definition_version.default_config_snapshot.dig("model_slots", "research", "selector")
    assert_equal "role:summary", result.agent_definition_version.default_config_snapshot.dig("model_slots", "summary", "selector")
    assert_equal default_profile_catalog, result.agent_definition_version.profile_catalog
    assert_equal({ "definition_changed" => false, "agent_config_version" => 1 }, result.reconciliation_report)
    assert_equal result.agent_definition_version, registration[:agent_definition_version].reload
    assert_equal registration[:agent_definition_version], registration[:agent_connection].reload.agent_definition_version
    assert_equal(
      RuntimeCapabilityContract.build(
        execution_runtime: registration[:execution_runtime],
        agent_definition_version: result.agent_definition_version
      ).effective_tool_catalog,
      result.runtime_capability_contract.effective_tool_catalog
    )
  end
end
