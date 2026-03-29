require "test_helper"

class ToolBindings::ProjectCapabilitySnapshotTest < ActiveSupport::TestCase
  test "projects durable definitions and implementations from one capability snapshot" do
    context = build_governed_tool_context!

    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_environment: context.fetch(:execution_environment)
    )

    definitions = ToolDefinition.where(
      capability_snapshot: context.fetch(:capability_snapshot)
    ).order(:tool_name)

    assert_equal %w[compact_context shell_exec subagent_spawn], definitions.pluck(:tool_name)
    assert_equal "replaceable", definitions.find_by!(tool_name: "compact_context").governance_mode
    assert_equal "whitelist_only", definitions.find_by!(tool_name: "shell_exec").governance_mode
    assert_equal "reserved", definitions.find_by!(tool_name: "subagent_spawn").governance_mode

    shell_definition = definitions.find_by!(tool_name: "shell_exec")
    assert_equal %w[agent/shell_exec env/shell_exec],
      shell_definition.tool_implementations.order(:implementation_ref).pluck(:implementation_ref)
    assert_equal "env/shell_exec",
      shell_definition.tool_implementations.find_by!(default_for_snapshot: true).implementation_ref

    subagent_definition = definitions.find_by!(tool_name: "subagent_spawn")
    assert_equal "core_matrix/subagent_spawn",
      subagent_definition.tool_implementations.find_by!(default_for_snapshot: true).implementation_ref
  end
end
