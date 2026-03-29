require "test_helper"

module MCP
end

class MCP::StreamableHttpTransportTest < ActiveSupport::TestCase
  setup do
    @server = FakeStreamableHttpMcpServer.new.start
  end

  teardown do
    @server.shutdown
  end

  test "opens a session, reads the SSE acknowledgement, calls one tool, and closes the session" do
    transport = MCP::StreamableHttpTransport.new(base_url: @server.base_url)

    session = transport.initialize_session!(
      client_info: { "name" => "core-matrix-test", "version" => "1.0.0" }
    )
    events = transport.open_sse_stream!(session_id: session.fetch("session_id"))
    result = transport.call_tool!(
      session_id: session.fetch("session_id"),
      tool_name: "echo",
      arguments: { "message" => "hello" }
    )
    closed = transport.close_session!(session_id: session.fetch("session_id"))

    assert_match(/\Asession-\d+\z/, session.fetch("session_id"))
    assert_equal "notifications/ready", events.first.fetch("method")
    assert_equal "echo: hello", result.dig("content", 0, "text")
    assert_equal true, closed
  end
end
