require "test_helper"

class ToolBindings::FreezeForWorkflowNodeTest < ActiveSupport::TestCase
  test "freezes one governed binding per allowed tool on the workflow node boundary" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_environment: context.fetch(:execution_environment)
    )

    bindings = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: context.fetch(:workflow_node)
    ).includes(:tool_definition, :tool_implementation).order(:id).to_a

    assert_equal %w[compact_context exec_command subagent_spawn],
      bindings.map { |binding| binding.tool_definition.tool_name }.sort
    assert bindings.all? { |binding| binding.agent_task_run.nil? }
    assert bindings.all? { |binding| binding.workflow_node == context.fetch(:workflow_node) }
  end

  test "reuses an existing workflow-node-owned binding set" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_environment: context.fetch(:execution_environment)
    )

    first = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: context.fetch(:workflow_node)
    ).order(:id).pluck(:public_id)
    second = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: context.fetch(:workflow_node)
    ).order(:id).pluck(:public_id)

    assert_equal first, second
  end

  test "materializes round-scoped program tools that are absent from the static capability snapshot" do
    context = build_governed_tool_context!

    bindings = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: context.fetch(:workflow_node),
      tool_catalog: [
        {
          "tool_name" => "workspace_write_file",
          "tool_kind" => "effect_intent",
          "implementation_source" => "agent",
          "implementation_ref" => "fenix/runtime/workspace_write_file",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ]
    ).includes(:tool_definition, :tool_implementation)

    binding = bindings.detect { |entry| entry.tool_definition.tool_name == "workspace_write_file" }

    assert_equal ["workspace_write_file"], bindings.map { |entry| entry.tool_definition.tool_name }
    assert binding.present?
    assert_nil binding.agent_task_run
    assert_equal context.fetch(:workflow_node), binding.workflow_node
    assert_equal "fenix/runtime/workspace_write_file", binding.tool_implementation.implementation_ref
    assert_equal true, binding.binding_payload.fetch("round_scoped")
  end
end
