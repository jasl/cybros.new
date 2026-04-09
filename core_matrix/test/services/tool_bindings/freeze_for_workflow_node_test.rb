require "test_helper"

class ToolBindings::FreezeForWorkflowNodeTest < ActiveSupport::TestCase
  test "freezes one governed binding per allowed tool on the workflow node boundary" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      executor_program: context.fetch(:executor_program)
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
      executor_program: context.fetch(:executor_program)
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
          "implementation_ref" => "fenix/agent/workspace_write_file",
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
    assert_equal "fenix/agent/workspace_write_file", binding.tool_implementation.implementation_ref
    assert_equal true, binding.round_scoped
    assert_equal false, binding.parallel_safe
    assert_equal false, binding.tool_implementation.metadata.dig("execution_policy", "parallel_safe")
  end

  test "rejects round tool catalogs that try to override reserved core matrix tools" do
    context = build_governed_tool_context!

    error = assert_raises(ActiveRecord::RecordInvalid) do
      ProviderExecution::MaterializeRoundTools.call(
        workflow_node: context.fetch(:workflow_node),
        tool_catalog: [
          {
            "tool_name" => "subagent_spawn",
            "tool_kind" => "effect_intent",
            "implementation_source" => "agent",
            "implementation_ref" => "fenix/agent/subagent_spawn",
            "input_schema" => { "type" => "object", "properties" => {} },
            "result_schema" => { "type" => "object", "properties" => {} },
            "streaming_support" => false,
            "idempotency_policy" => "best_effort",
          },
        ]
      )
    end

    assert_includes error.record.errors.full_messages.join(", "), "round tool catalog must not override reserved core matrix tool subagent_spawn"
  end

  test "freezes default execution policy onto workflow-node-owned bindings" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      executor_program: context.fetch(:executor_program)
    )

    binding = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: context.fetch(:workflow_node)
    ).includes(:tool_definition, :tool_implementation).find { |entry| entry.tool_definition.tool_name == "compact_context" }

    assert_equal false, binding.parallel_safe
    assert_equal false, binding.round_scoped
    assert_equal false, binding.tool_implementation.metadata.dig("execution_policy", "parallel_safe")
  end
end
