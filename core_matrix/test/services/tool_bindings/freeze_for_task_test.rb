require "test_helper"

class ToolBindings::FreezeForTaskTest < ActiveSupport::TestCase
  test "freezes one governed binding per allowed tool on the agent task boundary" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      executor_program: context.fetch(:executor_program)
    )

    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))

    bindings = task_run.reload.tool_bindings.includes(:tool_definition, :tool_implementation).order(:id).to_a

    assert_equal %w[compact_context exec_command subagent_spawn], bindings.map { |binding| binding.tool_definition.tool_name }.sort
    assert_equal "env/exec_command",
      bindings.find { |binding| binding.tool_definition.tool_name == "exec_command" }.tool_implementation.implementation_ref
    assert_equal "agent/compact_context",
      bindings.find { |binding| binding.tool_definition.tool_name == "compact_context" }.tool_implementation.implementation_ref
    assert_equal "core_matrix/subagent_spawn",
      bindings.find { |binding| binding.tool_definition.tool_name == "subagent_spawn" }.tool_implementation.implementation_ref
  end

  test "new attempts get a new frozen binding set instead of mutating the prior attempt" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      executor_program: context.fetch(:executor_program)
    )

    first_attempt = create_agent_task_run!(workflow_node: context.fetch(:workflow_node), logical_work_id: "tool-task", attempt_no: 1)
    second_attempt = create_agent_task_run!(workflow_node: context.fetch(:workflow_node), logical_work_id: "tool-task", attempt_no: 2)

    assert_equal %w[compact_context exec_command subagent_spawn],
      first_attempt.reload.tool_bindings.includes(:tool_definition).map { |binding| binding.tool_definition.tool_name }.sort
    assert_equal %w[compact_context exec_command subagent_spawn],
      second_attempt.reload.tool_bindings.includes(:tool_definition).map { |binding| binding.tool_definition.tool_name }.sort
    refute_equal first_attempt.tool_bindings.order(:id).pluck(:public_id),
      second_attempt.tool_bindings.order(:id).pluck(:public_id)
  end
end
