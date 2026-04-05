require "test_helper"

class ToolBindingTest < ActiveSupport::TestCase
  test "can bind a governed tool directly to a workflow node" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_runtime: context.fetch(:execution_runtime)
    )

    definition = ToolDefinition.find_by!(
      agent_program_version: context.fetch(:agent_program_version),
      tool_name: "compact_context"
    )
    implementation = definition.tool_implementations.find_by!(
      implementation_ref: "agent/compact_context"
    )

    binding = ToolBinding.new(
      installation: context.fetch(:workflow_node).installation,
      workflow_node: context.fetch(:workflow_node),
      tool_definition: definition,
      tool_implementation: implementation,
      binding_reason: "snapshot_default",
      runtime_state: {}
    )

    assert binding.valid?
  end

  test "belongs to the same installation and task projection as its binding target" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_runtime: context.fetch(:execution_runtime)
    )

    definition = ToolDefinition.find_by!(
      agent_program_version: context.fetch(:agent_program_version),
      tool_name: "compact_context"
    )
    implementation = definition.tool_implementations.find_by!(
      implementation_ref: "agent/compact_context"
    )
    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))

    other_installation = Installation.new(
      name: "Other installation",
      bootstrap_state: "bootstrapped",
      global_settings: {}
    )
    invalid_binding = ToolBinding.new(
      installation: other_installation,
      agent_task_run: task_run,
      tool_definition: definition,
      tool_implementation: implementation,
      binding_reason: "snapshot_default",
      runtime_state: {}
    )

    assert_not invalid_binding.valid?
    assert_includes invalid_binding.errors[:installation], "must match the task installation"
  end

  test "freezes at most one binding per task and tool definition" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_runtime: context.fetch(:execution_runtime)
    )

    definition = ToolDefinition.find_by!(
      agent_program_version: context.fetch(:agent_program_version),
      tool_name: "compact_context"
    )
    implementation = definition.tool_implementations.find_by!(
      implementation_ref: "agent/compact_context"
    )
    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))

    duplicate = ToolBinding.new(
      installation: task_run.installation,
      agent_task_run: task_run,
      tool_definition: definition,
      tool_implementation: implementation,
      binding_reason: "snapshot_default",
      runtime_state: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:tool_definition], "has already been bound for the task"
  end

  test "freezes at most one workflow-node-owned binding per tool definition" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_runtime: context.fetch(:execution_runtime)
    )

    definition = ToolDefinition.find_by!(
      agent_program_version: context.fetch(:agent_program_version),
      tool_name: "compact_context"
    )
    implementation = definition.tool_implementations.find_by!(
      implementation_ref: "agent/compact_context"
    )

    ToolBinding.create!(
      installation: context.fetch(:workflow_node).installation,
      workflow_node: context.fetch(:workflow_node),
      tool_definition: definition,
      tool_implementation: implementation,
      binding_reason: "snapshot_default",
      runtime_state: {}
    )

    duplicate = ToolBinding.new(
      installation: context.fetch(:workflow_node).installation,
      workflow_node: context.fetch(:workflow_node),
      tool_definition: definition,
      tool_implementation: implementation,
      binding_reason: "snapshot_default",
      runtime_state: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:tool_definition], "has already been bound for the workflow node"
  end

  test "preserves frozen execution policy as structured columns" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_runtime: context.fetch(:execution_runtime)
    )

    binding = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: context.fetch(:workflow_node)
    ).find { |entry| entry.tool_definition.tool_name == "compact_context" }

    assert_equal false, binding.parallel_safe
    assert_equal false, binding.round_scoped
    assert_equal({}, binding.runtime_state)
  end
end
