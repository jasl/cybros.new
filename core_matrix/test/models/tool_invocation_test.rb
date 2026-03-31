require "test_helper"

class ToolInvocationTest < ActiveSupport::TestCase
  test "can stay aligned with a workflow-node-owned binding" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_environment: context.fetch(:execution_environment)
    )

    binding = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: context.fetch(:workflow_node)
    ).joins(:tool_definition).find_by!(tool_definitions: { tool_name: "compact_context" })

    invocation = ToolInvocation.new(
      installation: context.fetch(:workflow_node).installation,
      workflow_node: context.fetch(:workflow_node),
      tool_binding: binding,
      tool_definition: binding.tool_definition,
      tool_implementation: binding.tool_implementation,
      status: "running",
      request_payload: {},
      response_payload: {},
      error_payload: {},
      attempt_no: 1,
      started_at: Time.current
    )

    assert invocation.valid?
  end

  test "requires invocation records to stay aligned with the frozen binding" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_environment: context.fetch(:execution_environment)
    )

    definition = ToolDefinition.find_by!(
      capability_snapshot: context.fetch(:capability_snapshot),
      tool_name: "compact_context"
    )
    implementation = definition.tool_implementations.find_by!(
      implementation_ref: "agent/compact_context"
    )
    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))
    binding = task_run.reload.tool_bindings.find_by!(
      tool_definition: definition,
      tool_implementation: implementation
    )

    invalid_invocation = ToolInvocation.new(
      installation: task_run.installation,
      agent_task_run: task_run,
      tool_binding: binding,
      tool_definition: definition,
      tool_implementation: definition.tool_implementations.create!(
        installation: task_run.installation,
        implementation_source: ImplementationSource.create!(
          installation: task_run.installation,
          source_kind: "agent",
          source_ref: "agent-runtime-alt",
          metadata: {}
        ),
        implementation_ref: "agent/compact_context_alt",
        input_schema: { "type" => "object", "properties" => {} },
        result_schema: { "type" => "object", "properties" => {} },
        streaming_support: false,
        idempotency_policy: "best_effort",
        default_for_snapshot: false,
        metadata: {}
      ),
      status: "running",
      request_payload: {},
      response_payload: {},
      error_payload: {},
      attempt_no: 1,
      started_at: Time.current
    )

    assert_not invalid_invocation.valid?
    assert_includes invalid_invocation.errors[:tool_implementation], "must match the frozen tool binding"
  end

  test "requires timestamps that match the invocation lifecycle" do
    invocation = ToolInvocation.new(
      installation: create_installation!,
      status: "succeeded",
      request_payload: {},
      response_payload: {},
      error_payload: {},
      attempt_no: 1,
      started_at: Time.current
    )

    assert_not invocation.valid?
    assert_includes invocation.errors[:finished_at], "must exist when the invocation is terminal"
  end
end
