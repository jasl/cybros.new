require "test_helper"

class RuntimeCapabilityContractTest < ActiveSupport::TestCase
  test "renders executor, agent, and effective projections from one contract" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      execution_runtime_capability_payload: { shell_access: true },
      execution_runtime_tool_catalog: [
        {
          tool_name: "exec_command",
          tool_kind: "execution_runtime",
          implementation_source: "execution_runtime",
          implementation_ref: "env/exec_command",
          input_schema: { type: "object", properties: {} },
          result_schema: { type: "object", properties: {} },
          streaming_support: false,
          idempotency_policy: "best_effort",
        },
      ],
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot,
      tool_catalog: [
        {
          tool_name: "exec_command",
          tool_kind: "agent_observation",
          implementation_source: "agent",
          implementation_ref: "agent/exec_command",
          input_schema: { type: "object", properties: {} },
          result_schema: { type: "object", properties: {} },
          streaming_support: false,
          idempotency_policy: "best_effort",
        },
        {
          tool_name: "compact_context",
          tool_kind: "agent_observation",
          implementation_source: "agent",
          implementation_ref: "agent/compact_context",
          input_schema: { type: "object", properties: {} },
          result_schema: { type: "object", properties: {} },
          streaming_support: false,
          idempotency_policy: "best_effort",
        },
      ]
    )
    contract = RuntimeCapabilityContract.build(
      execution_runtime: registration[:execution_runtime],
      agent_definition_version: registration[:agent_definition_version]
    )

    assert_equal "execution_runtime", contract.execution_runtime_plane.fetch("control_plane")
    assert_equal "agent", contract.agent_plane.fetch("control_plane")
    assert_equal default_profile_catalog, contract.agent_plane.fetch("profile_catalog")
    assert_equal default_profile_catalog, contract.contract_payload.fetch("profile_catalog")
    assert_equal "main", contract.default_config_snapshot.dig("interactive", "profile")
    assert_equal 3, contract.default_config_snapshot.dig("subagents", "max_depth")
    assert_nil contract.conversation_override_schema_snapshot.dig("properties", "interactive")
    assert_equal "boolean", contract.conversation_override_schema_snapshot.dig("properties", "subagents", "properties", "enabled", "type")
    assert_equal ["exec_command"], contract.execution_runtime_plane.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    assert_equal ["exec_command", "compact_context"], contract.effective_tool_catalog.map { |entry| entry.fetch("tool_name") }
    assert contract.execution_runtime_plane.fetch("tool_catalog").all? { |entry| entry.dig("execution_policy", "parallel_safe") == false }
    assert contract.agent_plane.fetch("tool_catalog").all? { |entry| entry.dig("execution_policy", "parallel_safe") == false }
    assert contract.effective_tool_catalog.all? { |entry| entry.dig("execution_policy", "parallel_safe") == false }
    response = contract.capability_response(
      method_id: "capabilities_handshake",
      execution_runtime_id: registration[:execution_runtime].public_id,
      execution_runtime_fingerprint: registration[:execution_runtime].execution_runtime_fingerprint
    )
    assert_equal registration[:execution_runtime].public_id, response.fetch("execution_runtime_id")
    assert_equal registration[:execution_runtime].execution_runtime_fingerprint, response.fetch("execution_runtime_fingerprint")
  end
end
