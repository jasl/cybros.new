require "test_helper"

class ToolBindings::SelectImplementationTest < ActiveSupport::TestCase
  test "reserved definitions keep the core matrix implementation even when a runtime alternative exists" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_runtime: context.fetch(:execution_runtime)
    )

    definition = ToolDefinition.find_by!(
      agent_program_version: context.fetch(:capability_snapshot),
      tool_name: "subagent_spawn"
    )
    runtime_override = definition.tool_implementations.find_by!(
      implementation_ref: "agent/subagent_spawn"
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      ToolBindings::SelectImplementation.call(
        tool_definition: definition,
        preferred_implementation: runtime_override
      )
    end

    assert_includes error.record.errors[:tool_definition], "must use the reserved implementation"
  end

  test "whitelist only definitions reject non-default implementation overrides" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_runtime: context.fetch(:execution_runtime)
    )

    definition = ToolDefinition.find_by!(
      agent_program_version: context.fetch(:capability_snapshot),
      tool_name: "exec_command"
    )
    runtime_override = definition.tool_implementations.find_by!(
      implementation_ref: "agent/exec_command"
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      ToolBindings::SelectImplementation.call(
        tool_definition: definition,
        preferred_implementation: runtime_override
      )
    end

    assert_includes error.record.errors[:tool_definition], "must use the approved implementation"
  end

  test "replaceable definitions accept alternate implementations under the same logical tool" do
    context = build_governed_tool_context!
    ToolBindings::ProjectCapabilitySnapshot.call(
      capability_snapshot: context.fetch(:capability_snapshot),
      execution_runtime: context.fetch(:execution_runtime)
    )

    definition = ToolDefinition.find_by!(
      agent_program_version: context.fetch(:capability_snapshot),
      tool_name: "compact_context"
    )
    alternate = definition.tool_implementations.create!(
      installation: context.fetch(:installation),
      implementation_source: ImplementationSource.create!(
        installation: context.fetch(:installation),
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
    )

    selected = ToolBindings::SelectImplementation.call(
      tool_definition: definition,
      preferred_implementation: alternate
    )

    assert_equal alternate, selected
  end
end
