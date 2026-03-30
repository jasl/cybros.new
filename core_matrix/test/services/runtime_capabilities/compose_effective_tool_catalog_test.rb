require "test_helper"

class RuntimeCapabilities::ComposeEffectiveToolCatalogTest < ActiveSupport::TestCase
  RESERVED_SUBAGENT_TOOLS = %w[
    subagent_spawn
    subagent_send
    subagent_wait
    subagent_close
    subagent_list
  ].freeze

  test "delegates effective tool catalog rendering to the shared runtime capability contract" do
    registration = register_agent_runtime!(
      environment_tool_catalog: [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "environment_runtime",
          "implementation_source" => "execution_environment",
          "implementation_ref" => "env/exec_command",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ],
      tool_catalog: default_tool_catalog("exec_command", "compact_context")
    )
    contract = RuntimeCapabilityContract.build(
      execution_environment: registration[:execution_environment],
      capability_snapshot: registration[:capability_snapshot],
      core_matrix_tool_catalog: RuntimeCapabilities::ComposeEffectiveToolCatalog::CORE_MATRIX_TOOL_CATALOG
    )

    assert_equal(
      contract.effective_tool_catalog,
      RuntimeCapabilities::ComposeEffectiveToolCatalog.call(
        execution_environment: registration[:execution_environment],
        capability_snapshot: registration[:capability_snapshot]
      )
    )
  end

  test "injects reserved subagent tools into the base effective catalog" do
    registration = register_agent_runtime!(
      environment_tool_catalog: [],
      tool_catalog: default_tool_catalog("exec_command")
    )

    effective_catalog = RuntimeCapabilities::ComposeEffectiveToolCatalog.call(
      execution_environment: registration[:execution_environment],
      capability_snapshot: registration[:capability_snapshot]
    )

    assert_equal RESERVED_SUBAGENT_TOOLS, effective_catalog.first(RESERVED_SUBAGENT_TOOLS.length).map { |entry| entry.fetch("tool_name") }
    assert_equal "effect_intent", effective_catalog.first.fetch("tool_kind")
    assert_equal "core_matrix", effective_catalog.first.fetch("implementation_source")
  end

  test "reserved subagent tool names cannot be overridden by runtime tools" do
    registration = register_agent_runtime!(
      environment_tool_catalog: [
        {
          "tool_name" => "subagent_spawn",
          "tool_kind" => "environment_runtime",
          "implementation_source" => "execution_environment",
          "implementation_ref" => "env/subagent_spawn",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ],
      tool_catalog: default_tool_catalog("subagent_spawn", "exec_command")
    )

    effective_catalog = RuntimeCapabilities::ComposeEffectiveToolCatalog.call(
      execution_environment: registration[:execution_environment],
      capability_snapshot: registration[:capability_snapshot]
    )
    spawn_entry = effective_catalog.find { |entry| entry.fetch("tool_name") == "subagent_spawn" }

    assert_equal "effect_intent", spawn_entry.fetch("tool_kind")
    assert_equal "core_matrix", spawn_entry.fetch("implementation_source")
    assert_equal "core_matrix/subagent_spawn", spawn_entry.fetch("implementation_ref")
    assert_equal 1, effective_catalog.count { |entry| entry.fetch("tool_name") == "subagent_spawn" }
  end
end
