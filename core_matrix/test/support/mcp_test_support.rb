module McpTestSupport
  private

  def governed_mcp_tool_catalog(base_url:, tool_name: "remote_echo", mcp_tool_name: "echo")
    [
      {
        "tool_name" => tool_name,
        "tool_kind" => "agent_observation",
        "implementation_source" => "mcp",
        "implementation_ref" => "mcp/#{mcp_tool_name}",
        "transport_kind" => "streamable_http",
        "server_url" => base_url,
        "mcp_tool_name" => mcp_tool_name,
        "input_schema" => { "type" => "object", "properties" => { "message" => { "type" => "string" } } },
        "result_schema" => { "type" => "object", "properties" => {} },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
      },
    ]
  end

  def governed_mcp_profile_catalog(tool_name: "remote_echo")
    {
      "main" => {
        "label" => "Main",
        "description" => "Primary interactive profile",
        "allowed_tool_names" => [tool_name],
      },
    }
  end

  def build_governed_mcp_context!(base_url:, tool_name: "remote_echo", mcp_tool_name: "echo")
    context = build_agent_control_context!
    capability_snapshot = create_capability_snapshot!(
      agent_program_version: context.fetch(:deployment),
      version: 2,
      tool_catalog: governed_mcp_tool_catalog(base_url: base_url, tool_name: tool_name, mcp_tool_name: mcp_tool_name),
      profile_catalog: governed_mcp_profile_catalog(tool_name: tool_name),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      conversation_override_schema_snapshot: { "type" => "object", "properties" => {} },
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    adopt_agent_program_version!(context, capability_snapshot)

    context.merge(
      capability_snapshot: context.fetch(:agent_program_version),
      turn: context.fetch(:turn).reload,
      workflow_node: context.fetch(:workflow_node).reload
    )
  end
end

ActiveSupport::TestCase.include(McpTestSupport)
ActionDispatch::IntegrationTest.include(McpTestSupport)
