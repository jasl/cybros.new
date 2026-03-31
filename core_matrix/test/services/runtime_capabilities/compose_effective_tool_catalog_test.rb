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
    assert_equal true,
      effective_catalog.find { |entry| entry.fetch("tool_name") == "subagent_list" }.dig("execution_policy", "parallel_safe")
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

  test "adds a default execution policy with parallel_safe false to effective tools" do
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

    effective_catalog = RuntimeCapabilities::ComposeEffectiveToolCatalog.call(
      execution_environment: registration[:execution_environment],
      capability_snapshot: registration[:capability_snapshot]
    )

    assert effective_catalog.present?
    assert effective_catalog.all? { |entry| entry["execution_policy"].is_a?(Hash) }
    assert effective_catalog.reject { |entry| entry.fetch("tool_name") == "subagent_list" }.all? do |entry|
      entry.dig("execution_policy", "parallel_safe") == false
    end
  end

  test "keeps mcp tools parallel_safe false by default in the effective catalog" do
    registration = register_agent_runtime!(
      tool_catalog: [
        {
          "tool_name" => "remote_echo",
          "tool_kind" => "agent_observation",
          "implementation_source" => "mcp",
          "implementation_ref" => "mcp/echo",
          "mcp_server_slug" => "external-docs",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
          "execution_policy" => { "parallel_safe" => true },
        },
      ]
    )

    entry = RuntimeCapabilities::ComposeEffectiveToolCatalog.call(
      execution_environment: registration[:execution_environment],
      capability_snapshot: registration[:capability_snapshot]
    ).find { |candidate| candidate.fetch("tool_name") == "remote_echo" }

    assert_equal false, entry.dig("execution_policy", "parallel_safe")
  end

  test "applies matching tool policy overlays from the capability snapshot default config" do
    registration = register_agent_runtime!(
      tool_catalog: [
        {
          "tool_name" => "remote_echo",
          "tool_kind" => "agent_observation",
          "implementation_source" => "mcp",
          "implementation_ref" => "mcp/echo",
          "mcp_server_slug" => "internal-docs",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
        {
          "tool_name" => "remote_search",
          "tool_kind" => "agent_observation",
          "implementation_source" => "mcp",
          "implementation_ref" => "mcp/search",
          "mcp_server_slug" => "public-search",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ],
      default_config_snapshot: default_default_config_snapshot.deep_merge(
        "tool_policy_overlays" => [
          {
            "match" => {
              "tool_source" => "mcp",
              "server_slug" => "internal-docs",
              "tool_name" => "remote_echo",
            },
            "execution_policy" => {
              "parallel_safe" => true,
            },
          },
        ]
      )
    )

    effective_catalog = RuntimeCapabilities::ComposeEffectiveToolCatalog.call(
      execution_environment: registration[:execution_environment],
      capability_snapshot: registration[:capability_snapshot]
    )

    remote_echo = effective_catalog.find { |candidate| candidate.fetch("tool_name") == "remote_echo" }
    remote_search = effective_catalog.find { |candidate| candidate.fetch("tool_name") == "remote_search" }

    assert_equal true, remote_echo.dig("execution_policy", "parallel_safe")
    assert_equal false, remote_search.dig("execution_policy", "parallel_safe")
  end
end
