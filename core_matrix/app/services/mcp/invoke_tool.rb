module MCP
  class InvokeTool
    def self.call(...)
      new(...).call
    end

    def initialize(tool_binding:, request_payload:)
      @tool_binding = tool_binding
      @request_payload = request_payload
    end

    def call
      invocation = ToolInvocations::Start.call(
        tool_binding: @tool_binding,
        request_payload: @request_payload
      )

      session = ensure_session!
      result = transport.call_tool!(
        session_id: session.fetch("session_id"),
        tool_name: mcp_tool_name,
        arguments: @request_payload.fetch("arguments", {})
      )
      persist_session_state!(
        session_id: session.fetch("session_id"),
        session_state: "open",
        sse_events: session.fetch("sse_events", [])
      )

      ToolInvocations::Complete.call(
        tool_invocation: invocation,
        response_payload: result,
        metadata: {
          "mcp" => {
            "session_id" => session.fetch("session_id"),
            "tool_name" => mcp_tool_name,
          },
        }
      )
    rescue MCP::TransportError => error
      clear_session_state! if error.code == "session_not_found"
      fail_invocation!(invocation, error, classification: "transport")
    rescue MCP::ProtocolError => error
      fail_invocation!(invocation, error, classification: "protocol")
    rescue MCP::SemanticError => error
      fail_invocation!(invocation, error, classification: "semantic")
    end

    private

    def ensure_session!
      session_id = @tool_binding.reload.binding_payload.dig("mcp", "session_id")
      return { "session_id" => session_id, "sse_events" => [] } if session_id.present?

      session = transport.initialize_session!(
        client_info: {
          "name" => "core-matrix",
          "version" => "phase2",
        }
      )
      sse_events = transport.open_sse_stream!(session_id: session.fetch("session_id"))
      persist_session_state!(
        session_id: session.fetch("session_id"),
        session_state: "open",
        sse_events: sse_events,
        initialize_result: session.fetch("initialize_result")
      )

      session.merge("sse_events" => sse_events)
    end

    def transport
      @transport ||= MCP::StreamableHttpTransport.new(base_url: server_url)
    end

    def server_url
      implementation_metadata.fetch("server_url")
    end

    def mcp_tool_name
      implementation_metadata.fetch("mcp_tool_name")
    end

    def implementation_metadata
      @implementation_metadata ||= @tool_binding.tool_implementation.metadata
    end

    def persist_session_state!(session_id:, session_state:, sse_events:, initialize_result: nil)
      binding_payload = @tool_binding.reload.binding_payload.deep_dup
      binding_payload["mcp"] = {
        "transport_kind" => implementation_metadata.fetch("transport_kind"),
        "server_url" => server_url,
        "tool_name" => mcp_tool_name,
        "session_id" => session_id,
        "session_state" => session_state,
        "last_sse_event" => sse_events.last,
        "initialize_result" => initialize_result,
      }.compact
      @tool_binding.update!(binding_payload: binding_payload)
    end

    def clear_session_state!
      binding_payload = @tool_binding.reload.binding_payload.deep_dup
      binding_payload["mcp"] = binding_payload.fetch("mcp", {}).merge(
        "transport_kind" => implementation_metadata.fetch("transport_kind"),
        "server_url" => server_url,
        "tool_name" => mcp_tool_name,
        "session_id" => nil,
        "session_state" => "closed",
      )
      @tool_binding.update!(binding_payload: binding_payload)
    end

    def fail_invocation!(invocation, error, classification:)
      ToolInvocations::Fail.call(
        tool_invocation: invocation,
        error_payload: {
          "classification" => classification,
          "code" => error.code,
          "message" => error.message,
          "retryable" => error.retryable,
          "details" => error.details,
        },
        metadata: {
          "mcp" => {
            "tool_name" => implementation_metadata["mcp_tool_name"],
            "server_url" => implementation_metadata["server_url"],
          },
        }
      )
    end
  end
end
