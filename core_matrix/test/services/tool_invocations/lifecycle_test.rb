require "test_helper"

class ToolInvocations::LifecycleTest < ActiveSupport::TestCase
  test "records invocation lifecycle through the same model for reserved and runtime tools" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_runtime: context.fetch(:execution_runtime)
    )

    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))
    compact_binding = task_run.reload.tool_bindings.joins(:tool_definition).find_by!(tool_definition: { tool_name: "compact_context" })
    subagent_binding = task_run.reload.tool_bindings.joins(:tool_definition).find_by!(tool_definition: { tool_name: "subagent_spawn" })

    compact_invocation = ToolInvocations::Start.call(
      tool_binding: compact_binding,
      request_payload: { "conversation_id" => context.fetch(:conversation).public_id }
    )
    subagent_invocation = ToolInvocations::Start.call(
      tool_binding: subagent_binding,
      request_payload: { "conversation_id" => context.fetch(:conversation).public_id }
    )

    ToolInvocations::Complete.call(
      tool_invocation: compact_invocation,
      response_payload: { "summary" => "context compacted" }
    )
    ToolInvocations::Complete.call(
      tool_invocation: subagent_invocation,
      response_payload: { "subagent_session_id" => "subagent-session-public-id" }
    )

    assert_equal "succeeded", compact_invocation.reload.status
    assert_equal "succeeded", subagent_invocation.reload.status
    assert_equal compact_binding.tool_definition, compact_invocation.tool_definition
    assert_equal subagent_binding.tool_definition, subagent_invocation.tool_definition
  end

  test "increments attempt numbers per frozen binding" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_runtime: context.fetch(:execution_runtime)
    )

    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))
    binding = task_run.reload.tool_bindings.joins(:tool_definition).find_by!(tool_definition: { tool_name: "compact_context" })

    first = ToolInvocations::Start.call(tool_binding: binding, request_payload: {})
    first.update!(status: "failed", error_payload: { "message" => "boom" }, finished_at: Time.current)
    second = ToolInvocations::Start.call(tool_binding: binding, request_payload: {})

    assert_equal 1, first.attempt_no
    assert_equal 2, second.attempt_no
  end

  test "records invocation lifecycle for workflow-node-owned bindings" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_runtime: context.fetch(:execution_runtime)
    )

    binding = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: context.fetch(:workflow_node)
    ).joins(:tool_definition).find_by!(tool_definitions: { tool_name: "compact_context" })

    invocation = ToolInvocations::Start.call(
      tool_binding: binding,
      request_payload: { "conversation_id" => context.fetch(:conversation).public_id }
    )

    ToolInvocations::Complete.call(
      tool_invocation: invocation,
      response_payload: { "summary" => "workflow-node scoped tool completed" }
    )

    invocation.reload

    assert_equal "succeeded", invocation.status
    assert_nil invocation.agent_task_run
    assert_equal context.fetch(:workflow_node), invocation.workflow_node
  end

  test "terminal updates ignore stale copies once an invocation has already terminalized" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_runtime: context.fetch(:execution_runtime)
    )

    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))
    binding = task_run.reload.tool_bindings.joins(:tool_definition).find_by!(tool_definition: { tool_name: "compact_context" })

    invocation = ToolInvocations::Start.call(tool_binding: binding, request_payload: {})
    stale_copy = ToolInvocation.find(invocation.id)
    fresh_copy = ToolInvocation.find(invocation.id)

    ToolInvocations::Complete.call(
      tool_invocation: fresh_copy,
      response_payload: { "summary" => "done" },
      metadata: { "reported_via" => "execution_complete" }
    )

    ToolInvocations::Fail.call(
      tool_invocation: stale_copy,
      error_payload: { "message" => "stale failure" },
      metadata: { "reported_via" => "execution_fail" }
    )

    invocation.reload

    assert_equal "succeeded", invocation.status
    assert_equal({ "summary" => "done" }, invocation.response_payload)
    assert_equal({}, invocation.error_payload)
    assert_equal "execution_complete", invocation.metadata.fetch("reported_via")
  end
end
