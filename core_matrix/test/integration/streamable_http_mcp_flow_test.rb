require "test_helper"

module MCP
end

class StreamableHttpMcpFlowTest < ActionDispatch::IntegrationTest
  setup do
    @server = FakeStreamableHttpMcpServer.new.start
  end

  teardown do
    @server.shutdown
  end

  test "one governed Streamable HTTP MCP path reuses the same binding model and recovers after session loss" do
    context = build_governed_mcp_context!(base_url: @server.base_url)
    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))
    binding = task_run.reload.tool_bindings.joins(:tool_definition).find_by!(tool_definition: { tool_name: "remote_echo" })

    first = MCP::InvokeTool.call(
      tool_binding: binding,
      request_payload: { "arguments" => { "message" => "first" } }
    )
    @server.fail_next_tool_call_with_session_not_found!
    second = MCP::InvokeTool.call(
      tool_binding: binding.reload,
      request_payload: { "arguments" => { "message" => "second" } }
    )
    third = MCP::InvokeTool.call(
      tool_binding: binding.reload,
      request_payload: { "arguments" => { "message" => "third" } }
    )

    assert_equal %w[succeeded failed succeeded],
      task_run.reload.tool_invocations.order(:attempt_no).pluck(:status)
    assert_equal first.tool_binding, second.tool_binding
    assert_equal first.tool_binding, third.tool_binding
    assert_equal "transport", second.error_payload.fetch("classification")
    assert_equal "echo: third", third.response_payload.dig("content", 0, "text")
    assert_operator @server.issued_session_ids.uniq.length, :>=, 2
  end
end
