require "test_helper"

class RuntimeCapabilityContractTest < ActiveSupport::TestCase
  test "renders executor, agent, and effective projections from one contract" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      executor_capability_payload: { shell_access: true },
      executor_tool_catalog: [
        {
          tool_name: "exec_command",
          tool_kind: "executor_program",
          implementation_source: "executor_program",
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
      executor_program: registration[:executor_program],
      agent_program_version: registration[:deployment]
    )

    assert_equal "executor", contract.executor_plane.fetch("control_plane")
    assert_equal "program", contract.program_plane.fetch("control_plane")
    assert_equal default_profile_catalog, contract.program_plane.fetch("profile_catalog")
    assert_equal default_profile_catalog, contract.contract_payload.fetch("profile_catalog")
    assert_equal "main", contract.default_config_snapshot.dig("interactive", "profile")
    assert_equal 3, contract.default_config_snapshot.dig("subagents", "max_depth")
    assert_nil contract.conversation_override_schema_snapshot.dig("properties", "interactive")
    assert_equal "boolean", contract.conversation_override_schema_snapshot.dig("properties", "subagents", "properties", "enabled", "type")
    assert_equal ["exec_command"], contract.executor_plane.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    assert_equal ["exec_command", "compact_context"], contract.effective_tool_catalog.map { |entry| entry.fetch("tool_name") }
    assert contract.executor_plane.fetch("tool_catalog").all? { |entry| entry.dig("execution_policy", "parallel_safe") == false }
    assert contract.program_plane.fetch("tool_catalog").all? { |entry| entry.dig("execution_policy", "parallel_safe") == false }
    assert contract.effective_tool_catalog.all? { |entry| entry.dig("execution_policy", "parallel_safe") == false }
    response = contract.capability_response(
      method_id: "capabilities_handshake",
      executor_program_id: registration[:executor_program].public_id,
      executor_fingerprint: registration[:executor_program].executor_fingerprint
    )
    assert_equal registration[:executor_program].public_id, response.fetch("executor_program_id")
    assert_equal registration[:executor_program].executor_fingerprint, response.fetch("executor_fingerprint")
  end
end
