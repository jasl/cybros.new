require "test_helper"

class ToolInvocations::ProvisionTest < ActiveSupport::TestCase
  test "reuses an existing invocation for the same workflow node and idempotency key across bindings" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      execution_runtime: context.fetch(:execution_runtime)
    )

    original_binding = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: context.fetch(:workflow_node)
    ).joins(:tool_definition).find_by!(tool_definitions: { tool_name: "compact_context" })

    agent_task_run = create_agent_task_run!(
      workflow_node: context.fetch(:workflow_node),
      kind: "agent_tool_call",
      logical_work_id: "tool-call:#{context.fetch(:workflow_node).public_id}:call-shared"
    )
    duplicate_binding = agent_task_run.tool_bindings.find_by!(
      tool_definition: original_binding.tool_definition
    )

    first = ToolInvocations::Provision.call(
      tool_binding: original_binding,
      request_payload: { "arguments" => { "query" => "current task" } },
      idempotency_key: "call-shared"
    )
    second = ToolInvocations::Provision.call(
      tool_binding: duplicate_binding,
      request_payload: { "arguments" => { "query" => "current task" } },
      idempotency_key: "call-shared"
    )

    assert first.created
    assert_not second.created
    assert_equal first.tool_invocation.public_id, second.tool_invocation.public_id
    assert_equal 1, ToolInvocation.where(
      workflow_node: context.fetch(:workflow_node),
      idempotency_key: "call-shared"
    ).count
  end
end
