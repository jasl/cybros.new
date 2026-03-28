require "test_helper"

module CapabilitySnapshots
end

class CapabilitySnapshots::ReconcileTest < ActiveSupport::TestCase
  test "creates version one and activates it when the deployment has no snapshots" do
    deployment = create_agent_deployment!
    contract = RuntimeCapabilityContract.build(
      execution_environment: deployment.execution_environment,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake"),
      tool_catalog: default_tool_catalog("shell_exec", "subagent_spawn"),
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )

    snapshot = CapabilitySnapshots::Reconcile.call(
      deployment: deployment,
      runtime_capability_contract: contract
    )

    assert_equal 1, snapshot.version
    assert_equal snapshot, deployment.reload.active_capability_snapshot
    assert_equal default_profile_catalog, snapshot.profile_catalog
    assert_equal %w[shell_exec subagent_spawn], snapshot.tool_catalog.map { |entry| entry.fetch("tool_name") }
  end

  test "reuses and reactivates an existing matching snapshot" do
    deployment = create_agent_deployment!
    matching_snapshot = create_capability_snapshot!(
      agent_deployment: deployment,
      version: 1,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake"),
      tool_catalog: default_tool_catalog("shell_exec", "subagent_spawn"),
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    drifted_snapshot = create_capability_snapshot!(
      agent_deployment: deployment,
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake"),
      tool_catalog: default_tool_catalog("shell_exec"),
      profile_catalog: default_profile_catalog.deep_merge(
        "researcher" => { "allowed_tool_names" => %w[shell_exec] }
      ),
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    deployment.update!(active_capability_snapshot: drifted_snapshot)

    snapshot = CapabilitySnapshots::Reconcile.call(
      deployment: deployment,
      runtime_capability_contract: RuntimeCapabilityContract.build(capability_snapshot: matching_snapshot)
    )

    assert_equal matching_snapshot, snapshot
    assert_equal matching_snapshot, deployment.reload.active_capability_snapshot
    assert_equal [1, 2], deployment.capability_snapshots.order(:version).pluck(:version)
  end

  test "appends the next version when the runtime contract drifts" do
    deployment = create_agent_deployment!
    existing_snapshot = create_capability_snapshot!(
      agent_deployment: deployment,
      version: 1,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake"),
      tool_catalog: default_tool_catalog("shell_exec"),
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    deployment.update!(active_capability_snapshot: existing_snapshot)

    snapshot = CapabilitySnapshots::Reconcile.call(
      deployment: deployment,
      runtime_capability_contract: RuntimeCapabilityContract.build(
        execution_environment: deployment.execution_environment,
        protocol_methods: existing_snapshot.protocol_methods,
        tool_catalog: default_tool_catalog("shell_exec", "subagent_spawn"),
        profile_catalog: existing_snapshot.profile_catalog,
        config_schema_snapshot: existing_snapshot.config_schema_snapshot,
        conversation_override_schema_snapshot: existing_snapshot.conversation_override_schema_snapshot,
        default_config_snapshot: existing_snapshot.default_config_snapshot
      )
    )

    assert_equal 2, snapshot.version
    assert_equal snapshot, deployment.reload.active_capability_snapshot
    assert_equal [1, 2], deployment.capability_snapshots.order(:version).pluck(:version)
    assert_equal %w[shell_exec subagent_spawn], snapshot.tool_catalog.map { |entry| entry.fetch("tool_name") }
  end
end
