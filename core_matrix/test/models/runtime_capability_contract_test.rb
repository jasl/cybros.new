require "test_helper"

class RuntimeCapabilityContractTest < ActiveSupport::TestCase
  test "renders executor, agent, and effective projections from one contract" do
    registration = register_agent_runtime!(
      profile_policy: default_profile_policy,
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
      canonical_config_schema: profile_aware_canonical_config_schema,
      conversation_override_schema: subagent_policy_conversation_override_schema,
      default_canonical_config: profile_aware_default_canonical_config,
      tool_contract: [
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
    assert_equal "object", contract.agent_plane.dig("workspace_agent_settings_schema", "type")
    assert_equal "pragmatic", contract.agent_plane.dig("default_workspace_agent_settings", "agent", "interactive", "profile_key")
    assert_equal "main", contract.default_canonical_config.dig("interactive", "profile")
    assert_equal 3, contract.default_canonical_config.dig("subagents", "max_depth")
    assert_nil contract.conversation_override_schema.dig("properties", "interactive")
    assert_equal "boolean", contract.conversation_override_schema.dig("properties", "subagents", "properties", "enabled", "type")
    assert_equal ["exec_command"], contract.execution_runtime_plane.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    assert_equal ["exec_command", "compact_context"], contract.effective_tool_catalog.map { |entry| entry.fetch("tool_name") }
    assert contract.execution_runtime_plane.fetch("tool_catalog").all? { |entry| entry.dig("execution_policy", "parallel_safe") == false }
    assert contract.agent_plane.fetch("tool_contract").all? { |entry| entry.dig("execution_policy", "parallel_safe") == false }
    assert contract.effective_tool_catalog.all? { |entry| entry.dig("execution_policy", "parallel_safe") == false }
    response = contract.capability_response(
      method_id: "capabilities_handshake",
      execution_runtime_id: registration[:execution_runtime].public_id,
      execution_runtime_fingerprint: registration[:execution_runtime].execution_runtime_fingerprint
    )
    assert_equal registration[:execution_runtime].public_id, response.fetch("execution_runtime_id")
    assert_equal registration[:execution_runtime].execution_runtime_fingerprint, response.fetch("execution_runtime_fingerprint")
    assert_equal "object", response.dig("agent_plane", "workspace_agent_settings_schema", "type")
  end
end
