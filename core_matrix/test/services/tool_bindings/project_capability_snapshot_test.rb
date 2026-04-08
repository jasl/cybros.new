require "test_helper"

class ToolBindings::ProjectCapabilitySnapshotTest < ActiveSupport::TestCase
  test "projects durable definitions and implementations from one capability snapshot" do
    context = build_governed_tool_context!

    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      executor_program: context.fetch(:executor_program)
    )

    definitions = ToolDefinition.where(
      agent_program_version: context.fetch(:capability_snapshot)
    ).order(:tool_name)

    assert_equal %w[compact_context exec_command subagent_spawn], definitions.pluck(:tool_name)
    assert_equal "replaceable", definitions.find_by!(tool_name: "compact_context").governance_mode
    assert_equal "whitelist_only", definitions.find_by!(tool_name: "exec_command").governance_mode
    assert_equal "reserved", definitions.find_by!(tool_name: "subagent_spawn").governance_mode

    shell_definition = definitions.find_by!(tool_name: "exec_command")
    assert_equal %w[agent/exec_command env/exec_command],
      shell_definition.tool_implementations.order(:implementation_ref).pluck(:implementation_ref)
    assert_equal "env/exec_command",
      shell_definition.tool_implementations.find_by!(default_for_snapshot: true).implementation_ref
    assert_equal false, shell_definition.policy_payload.dig("execution_policy", "parallel_safe")
    assert shell_definition.tool_implementations.all? { |implementation| implementation.metadata.dig("execution_policy", "parallel_safe") == false }

    subagent_definition = definitions.find_by!(tool_name: "subagent_spawn")
    assert_equal "core_matrix/subagent_spawn",
      subagent_definition.tool_implementations.find_by!(default_for_snapshot: true).implementation_ref
    assert_equal false, subagent_definition.policy_payload.dig("execution_policy", "parallel_safe")
  end
end
