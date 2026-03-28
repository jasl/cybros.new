require "test_helper"

class RuntimeCapabilityContractTest < ActiveSupport::TestCase
  test "renders environment, agent, effective, and conversation-facing projections from one contract" do
    registration = register_agent_runtime!(
      environment_capability_payload: { conversation_attachment_upload: false },
      environment_tool_catalog: [
        {
          tool_name: "shell_exec",
          tool_kind: "environment_runtime",
          implementation_source: "execution_environment",
          implementation_ref: "env/shell_exec",
          input_schema: { type: "object", properties: {} },
          result_schema: { type: "object", properties: {} },
          streaming_support: false,
          idempotency_policy: "best_effort",
        },
      ],
      tool_catalog: [
        {
          tool_name: "shell_exec",
          tool_kind: "agent_observation",
          implementation_source: "agent",
          implementation_ref: "agent/shell_exec",
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
      execution_environment: registration[:execution_environment],
      capability_snapshot: registration[:capability_snapshot]
    )

    assert_equal "environment", contract.environment_plane.fetch("runtime_plane")
    assert_equal "agent", contract.agent_plane.fetch("runtime_plane")
    assert_equal ["shell_exec"], contract.environment_plane.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    assert_equal ["shell_exec", "compact_context"], contract.effective_tool_catalog.map { |entry| entry.fetch("tool_name") }
    assert_equal false, contract.conversation_payload(
      execution_environment_id: registration[:execution_environment].public_id,
      agent_deployment_id: registration[:deployment].public_id
    ).fetch("conversation_attachment_upload")
  end
end
