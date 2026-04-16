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

  def governed_mcp_profile_policy(tool_name: "remote_echo")
    {
      "pragmatic" => {
        "label" => "Pragmatic",
        "description" => "Primary pragmatic interactive profile",
        "allowed_tool_names" => [tool_name],
      },
      "friendly" => {
        "label" => "Friendly",
        "description" => "Friendly interactive profile",
        "allowed_tool_names" => [tool_name],
      },
    }
  end

  def build_governed_mcp_context!(base_url:, tool_name: "remote_echo", mcp_tool_name: "echo")
    context = build_agent_control_context!
    capability_snapshot = create_compatible_agent_definition_version!(
      agent_definition_version: context.fetch(:agent_definition_version),
      version: 2,
      tool_contract: governed_mcp_tool_catalog(base_url: base_url, tool_name: tool_name, mcp_tool_name: mcp_tool_name),
      profile_policy: governed_mcp_profile_policy(tool_name: tool_name),
      canonical_config_schema: default_canonical_config_schema(include_selector_slots: true),
      conversation_override_schema: { "type" => "object", "properties" => {} },
      default_canonical_config: default_default_canonical_config(include_selector_slots: true)
    )
    adopt_agent_definition_version!(context, capability_snapshot)

    context.merge(
      agent_definition_version: context.fetch(:agent_definition_version),
      turn: context.fetch(:turn).reload,
      workflow_node: context.fetch(:workflow_node).reload
    )
  end
end

ActiveSupport::TestCase.include(McpTestSupport)
ActionDispatch::IntegrationTest.include(McpTestSupport)
