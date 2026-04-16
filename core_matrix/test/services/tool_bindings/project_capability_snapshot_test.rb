require "test_helper"

class ToolBindings::ProjectCapabilitySnapshotTest < ActiveSupport::TestCase
  test "projects durable definitions and implementations from one capability snapshot" do
    context = build_governed_tool_context!

    ToolBindings::ProjectCapabilitySnapshot.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      execution_runtime: context.fetch(:execution_runtime)
    )

    definitions = ToolDefinition.where(
      agent_definition_version: context.fetch(:agent_definition_version)
    ).order(:tool_name)

    assert_equal %w[
      compact_context
      conversation_metadata_update
      exec_command
      subagent_close
      subagent_list
      subagent_send
      subagent_spawn
      subagent_wait
    ], definitions.pluck(:tool_name)
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

  test "projects runtime-backed tools alongside the full reserved core matrix surface" do
    context = build_governed_tool_context!(
      agent_tool_catalog: [
        {
          "tool_name" => "compact_context",
          "tool_kind" => "agent_observation",
          "implementation_source" => "agent",
          "implementation_ref" => "agent/compact_context",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ]
    )

    ToolBindings::ProjectCapabilitySnapshot.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      execution_runtime: context.fetch(:execution_runtime)
    )

    definitions = ToolDefinition.where(
      agent_definition_version: context.fetch(:agent_definition_version)
    ).order(:tool_name)

    assert_equal %w[
      compact_context
      conversation_metadata_update
      exec_command
      subagent_close
      subagent_list
      subagent_send
      subagent_spawn
      subagent_wait
    ], definitions.pluck(:tool_name)
    assert_equal "whitelist_only", definitions.find_by!(tool_name: "exec_command").governance_mode
  end
end
