require "test_helper"

class ToolInvocationTest < ActiveSupport::TestCase
  test "can stay aligned with a workflow-node-owned binding" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      execution_runtime: context.fetch(:execution_runtime)
    )

    binding = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: context.fetch(:workflow_node)
    ).joins(:tool_definition).find_by!(tool_definitions: { tool_name: "compact_context" })

    invocation = ToolInvocation.new(
      installation: context.fetch(:workflow_node).installation,
      user: context.fetch(:workflow_node).user,
      workspace: context.fetch(:workflow_node).workspace,
      agent: context.fetch(:workflow_node).agent,
      workflow_node: context.fetch(:workflow_node),
      conversation: context.fetch(:workflow_node).conversation,
      turn: context.fetch(:workflow_node).turn,
      workflow_run: context.fetch(:workflow_node).workflow_run,
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
      agent_definition_version: context.fetch(:agent_definition_version),
      execution_runtime: context.fetch(:execution_runtime)
    )

    definition = ToolDefinition.find_by!(
      agent_definition_version: context.fetch(:agent_definition_version),
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
      user: task_run.user,
      workspace: task_run.workspace,
      agent: task_run.agent,
      agent_task_run: task_run,
      conversation: task_run.conversation,
      turn: task_run.turn,
      workflow_run: task_run.workflow_run,
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

  test "requires duplicated owner context to match the execution subject" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      execution_runtime: context.fetch(:execution_runtime)
    )
    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))
    binding = task_run.reload.tool_bindings.joins(:tool_definition).find_by!(tool_definitions: { tool_name: "compact_context" })
    foreign = create_workspace_context!

    invocation = ToolInvocation.new(
      installation: task_run.installation,
      agent_task_run: task_run,
      workflow_node: task_run.workflow_node,
      tool_binding: binding,
      tool_definition: binding.tool_definition,
      tool_implementation: binding.tool_implementation,
      user_id: foreign[:user].id,
      workspace_id: foreign[:workspace].id,
      agent_id: foreign[:agent].id,
      conversation_id: task_run.conversation_id,
      turn_id: task_run.turn_id,
      workflow_run_id: task_run.workflow_run_id,
      status: "running",
      request_payload: {},
      response_payload: {},
      error_payload: {},
      attempt_no: 1,
      started_at: Time.current
    )

    assert_not invocation.valid?
    assert_includes invocation.errors[:user], "must match the execution subject user"
    assert_includes invocation.errors[:workspace], "must match the execution subject workspace"
    assert_includes invocation.errors[:agent], "must match the execution subject agent"
  end
end
