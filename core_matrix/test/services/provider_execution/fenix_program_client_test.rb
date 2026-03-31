require "test_helper"

class ProviderExecution::FenixProgramClientTest < ActiveSupport::TestCase
  test "posts prepare_round payloads to the registered fenix runtime endpoint" do
    context = create_workspace_context!
    context.fetch(:agent_deployment).update!(
      endpoint_metadata: {
        "transport" => "http",
        "base_url" => "https://fenix.example.test",
        "prepare_round_path" => "/runtime/rounds/prepare",
        "execute_program_tool_path" => "/runtime/program_tools/execute",
      }
    )
    transport = ProviderExecutionTestSupport::FakeJsonTransport.new(
      response: ProviderExecutionTestSupport::FakeHttpResponse.new(
        code: "200",
        body: JSON.generate({ "messages" => [], "program_tools" => [] }),
        headers: {}
      )
    )

    result = ProviderExecution::FenixProgramClient.new(
      agent_deployment: context.fetch(:agent_deployment),
      transport: transport
    ).prepare_round(body: { "workflow_node_id" => "workflow-node-public-id" })

    assert_equal({ "messages" => [], "program_tools" => [] }, result)
    assert_equal "https://fenix.example.test/runtime/rounds/prepare", transport.last_uri.to_s
    assert_equal :post, transport.last_method
    assert_equal "application/json", transport.last_headers.fetch("Content-Type")
    assert_equal({ "workflow_node_id" => "workflow-node-public-id" }, JSON.parse(transport.last_body))
  end

  test "raises a transport error when fenix returns a non-success status" do
    context = create_workspace_context!
    context.fetch(:agent_deployment).update!(
      endpoint_metadata: {
        "transport" => "http",
        "base_url" => "https://fenix.example.test",
        "prepare_round_path" => "/runtime/rounds/prepare",
        "execute_program_tool_path" => "/runtime/program_tools/execute",
      }
    )
    transport = ProviderExecutionTestSupport::FakeJsonTransport.new(
      response: ProviderExecutionTestSupport::FakeHttpResponse.new(
        code: "503",
        body: JSON.generate({ "error" => "temporarily unavailable" }),
        headers: {}
      )
    )

    error = assert_raises(ProviderExecution::FenixProgramClient::TransportError) do
      ProviderExecution::FenixProgramClient.new(
        agent_deployment: context.fetch(:agent_deployment),
        transport: transport
      ).prepare_round(body: {})
    end

    assert_equal "http_error", error.code
    assert_equal true, error.retryable
  end

  test "returns structured tool failures even when fenix uses a non-success status code" do
    context = create_workspace_context!
    context.fetch(:agent_deployment).update!(
      endpoint_metadata: {
        "transport" => "http",
        "base_url" => "https://fenix.example.test",
        "prepare_round_path" => "/runtime/rounds/prepare",
        "execute_program_tool_path" => "/runtime/program_tools/execute",
      }
    )
    transport = ProviderExecutionTestSupport::FakeJsonTransport.new(
      response: ProviderExecutionTestSupport::FakeHttpResponse.new(
        code: "500",
        body: JSON.generate(
          {
            "status" => "failed",
            "tool_call" => {
              "call_id" => "call-123",
              "tool_name" => "write_stdin",
              "arguments" => { "command_run_id" => "command-run-123" },
            },
            "error" => {
              "classification" => "runtime",
              "code" => "runtime_error",
              "message" => "unknown command run command-run-123",
              "retryable" => false,
            },
          }
        ),
        headers: {}
      )
    )

    result = ProviderExecution::FenixProgramClient.new(
      agent_deployment: context.fetch(:agent_deployment),
      transport: transport
    ).execute_program_tool(body: { "tool_name" => "write_stdin" })

    assert_equal "failed", result.fetch("status")
    assert_equal "runtime_error", result.dig("error", "code")
    assert_equal "unknown command run command-run-123", result.dig("error", "message")
  end
end
