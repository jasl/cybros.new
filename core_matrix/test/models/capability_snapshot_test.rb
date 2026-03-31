require "test_helper"

class CapabilitySnapshotTest < ActiveSupport::TestCase
  test "versions snapshots and treats them as immutable" do
    deployment = create_agent_deployment!
    snapshot = create_capability_snapshot!(
      agent_deployment: deployment,
      version: 1,
      protocol_methods: default_protocol_methods("agent_health"),
      tool_catalog: default_tool_catalog("exec_command")
    )
    create_capability_snapshot!(
      agent_deployment: deployment,
      version: 2,
      protocol_methods: default_protocol_methods("capabilities_handshake"),
      tool_catalog: default_tool_catalog("subagent_spawn")
    )

    assert_equal [1, 2], deployment.capability_snapshots.order(:version).pluck(:version)

    assert_raises(ActiveRecord::ReadOnlyRecord) do
      snapshot.update!(default_config_snapshot: { "mode" => "changed" })
    end
  end

  test "round trips profile catalogs through snapshot persistence" do
    assert_includes CapabilitySnapshot.column_names, "profile_catalog"

    snapshot = create_capability_snapshot!(
      profile_catalog: default_profile_catalog
    )

    assert_equal default_profile_catalog, snapshot.reload.profile_catalog
  end

  test "renders outward payloads through the shared runtime capability contract" do
    snapshot = create_capability_snapshot!(
      tool_catalog: default_tool_catalog("exec_command"),
      protocol_methods: default_protocol_methods("agent_health")
    )
    contract = RuntimeCapabilityContract.build(capability_snapshot: snapshot)
    normalized_tool_catalog = contract.agent_plane.fetch("tool_catalog")

    assert_equal(
      {
        "agent_capabilities_version" => snapshot.version,
        "protocol_methods" => snapshot.protocol_methods,
        "tool_catalog" => normalized_tool_catalog,
        "profile_catalog" => snapshot.profile_catalog,
        "config_schema_snapshot" => snapshot.config_schema_snapshot,
        "conversation_override_schema_snapshot" => snapshot.conversation_override_schema_snapshot,
        "default_config_snapshot" => snapshot.default_config_snapshot,
      },
      contract.contract_payload
    )
    assert_equal normalized_tool_catalog, contract.agent_plane.fetch("tool_catalog")
    assert_equal snapshot.profile_catalog, contract.agent_plane.fetch("profile_catalog")
  end

  test "matches runtime contracts across the full agent-plane surface" do
    snapshot = create_capability_snapshot!(
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake"),
      tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )

    matching_contract = RuntimeCapabilityContract.build(
      capability_snapshot: snapshot
    )
    drifted_contract = RuntimeCapabilityContract.build(
      protocol_methods: snapshot.protocol_methods,
      tool_catalog: snapshot.tool_catalog,
      profile_catalog: default_profile_catalog.deep_merge(
        "researcher" => { "allowed_tool_names" => %w[exec_command] }
      ),
      config_schema_snapshot: snapshot.config_schema_snapshot,
      conversation_override_schema_snapshot: snapshot.conversation_override_schema_snapshot,
      default_config_snapshot: snapshot.default_config_snapshot
    )

    assert snapshot.matches_runtime_capability_contract?(matching_contract)
    assert_not snapshot.matches_runtime_capability_contract?(drifted_contract)
  end
end
