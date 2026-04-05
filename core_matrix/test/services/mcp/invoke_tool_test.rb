require "test_helper"

module MCP
end

class MCP::InvokeToolTest < ActiveSupport::TestCase
  setup do
    @server = FakeStreamableHttpMcpServer.new.start
  end

  teardown do
    @server.shutdown
  end

  test "records a governed MCP invocation and persists session state on the binding" do
    context = build_governed_mcp_context!(base_url: @server.base_url)
    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))
    binding = task_run.reload.tool_bindings.joins(:tool_definition).find_by!(tool_definition: { tool_name: "remote_echo" })

    invocation = MCP::InvokeTool.call(
      tool_binding: binding,
      request_payload: { "arguments" => { "message" => "hello" } }
    )

    assert_equal "succeeded", invocation.reload.status
    assert_equal "echo: hello", invocation.response_payload.dig("content", 0, "text")
    assert_match(/\Asession-\d+\z/, binding.reload.runtime_state.dig("mcp", "session_id"))
  end

  test "classifies session_not_found as a retryable transport failure and clears the stored session" do
    context = build_governed_mcp_context!(base_url: @server.base_url)
    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))
    binding = task_run.reload.tool_bindings.joins(:tool_definition).find_by!(tool_definition: { tool_name: "remote_echo" })

    MCP::InvokeTool.call(
      tool_binding: binding,
      request_payload: { "arguments" => { "message" => "first" } }
    )
    @server.fail_next_tool_call_with_session_not_found!

    failed = MCP::InvokeTool.call(
      tool_binding: binding.reload,
      request_payload: { "arguments" => { "message" => "second" } }
    )

    assert_equal "failed", failed.reload.status
    assert_equal "transport", failed.error_payload.fetch("classification")
    assert_equal "session_not_found", failed.error_payload.fetch("code")
    assert_equal true, failed.error_payload.fetch("retryable")
    assert_nil binding.reload.runtime_state.dig("mcp", "session_id")
  end

  test "classifies malformed JSON-RPC responses as protocol failures" do
    context = build_governed_mcp_context!(base_url: @server.base_url)
    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))
    binding = task_run.reload.tool_bindings.joins(:tool_definition).find_by!(tool_definition: { tool_name: "remote_echo" })
    @server.fail_next_tool_call_with_protocol_error!

    failed = MCP::InvokeTool.call(
      tool_binding: binding,
      request_payload: { "arguments" => { "message" => "broken" } }
    )

    assert_equal "failed", failed.reload.status
    assert_equal "protocol", failed.error_payload.fetch("classification")
    assert_equal "invalid_json_rpc_response", failed.error_payload.fetch("code")
    assert_equal false, failed.error_payload.fetch("retryable")
  end

  test "classifies remote tool errors as semantic failures" do
    context = build_governed_mcp_context!(base_url: @server.base_url)
    task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))
    binding = task_run.reload.tool_bindings.joins(:tool_definition).find_by!(tool_definition: { tool_name: "remote_echo" })
    @server.fail_next_tool_call_with_semantic_error!

    failed = MCP::InvokeTool.call(
      tool_binding: binding,
      request_payload: { "arguments" => { "message" => "explode" } }
    )

    assert_equal "failed", failed.reload.status
    assert_equal "semantic", failed.error_payload.fetch("classification")
    assert_equal "tool_error", failed.error_payload.fetch("code")
    assert_equal false, failed.error_payload.fetch("retryable")
  end
end
