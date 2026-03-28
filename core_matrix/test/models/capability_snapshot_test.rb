require "test_helper"

class CapabilitySnapshotTest < ActiveSupport::TestCase
  test "versions snapshots and treats them as immutable" do
    deployment = create_agent_deployment!
    snapshot = create_capability_snapshot!(
      agent_deployment: deployment,
      version: 1,
      protocol_methods: default_protocol_methods("agent_health"),
      tool_catalog: default_tool_catalog("shell_exec")
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

  test "renders outward payloads through the shared runtime capability contract" do
    snapshot = create_capability_snapshot!(
      tool_catalog: default_tool_catalog("shell_exec"),
      protocol_methods: default_protocol_methods("agent_health")
    )
    contract = RuntimeCapabilityContract.build(capability_snapshot: snapshot)

    assert_equal contract.contract_payload(method_id: "capabilities_refresh"), snapshot.as_contract_payload(method_id: "capabilities_refresh")
    assert_equal contract.agent_plane, snapshot.as_agent_plane_payload
  end
end
