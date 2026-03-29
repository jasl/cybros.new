require "json"
require "net/http"
require "securerandom"
require "uri"

module MCP
  class TransportError < StandardError
    attr_reader :code, :details, :retryable

    def initialize(code:, message:, details: {}, retryable: false)
      @code = code
      @details = details
      @retryable = retryable
      super(message)
    end
  end

  class ProtocolError < StandardError
    attr_reader :code, :details, :retryable

    def initialize(code:, message:, details: {}, retryable: false)
      @code = code
      @details = details
      @retryable = retryable
      super(message)
    end
  end

  class SemanticError < StandardError
    attr_reader :code, :details, :retryable

    def initialize(code:, message:, details: {}, retryable: false)
      @code = code
      @details = details
      @retryable = retryable
      super(message)
    end
  end

  class StreamableHttpTransport
    DEFAULT_PROTOCOL_VERSION = "2024-11-05".freeze

    def initialize(base_url:, headers: {}, open_timeout: 5, read_timeout: 5, protocol_version: DEFAULT_PROTOCOL_VERSION)
      @uri = URI.parse(base_url)
      @headers = headers
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @protocol_version = protocol_version
    end

    def initialize_session!(client_info:)
      payload, headers = post_json_rpc(
        method: "initialize",
        params: {
          "protocolVersion" => @protocol_version,
          "capabilities" => {},
          "clientInfo" => client_info,
        }
      )
      session_id = headers.fetch("mcp-session-id", nil)
      raise ProtocolError.new(code: "missing_session_id", message: "initialize response did not include Mcp-Session-Id") if session_id.blank?

      notifications_initialized!(session_id:)

      {
        "session_id" => session_id,
        "initialize_result" => payload.fetch("result"),
      }
    end

    def open_sse_stream!(session_id:)
      response = with_http do |http|
        request = Net::HTTP::Get.new(@uri)
        default_headers(
          {
            "Accept" => "text/event-stream",
            "Cache-Control" => "no-cache",
            "Mcp-Session-Id" => session_id,
          }
        ).each { |key, value| request[key] = value }
        http.request(request)
      end

      status = response.code.to_i
      if status == 404
        raise TransportError.new(code: "session_not_found", message: "MCP session was not found", retryable: true)
      end

      unless status.between?(200, 299)
        raise TransportError.new(code: "http_error", message: "unexpected SSE response status #{status}", details: { "status" => status }, retryable: true)
      end

      content_type = header_value(response, "content-type")
      unless content_type.include?("text/event-stream")
        raise ProtocolError.new(code: "invalid_sse_content_type", message: "SSE endpoint did not return text/event-stream", details: { "content_type" => content_type })
      end

      parse_sse_events(response.body.to_s)
    end

    def call_tool!(session_id:, tool_name:, arguments:)
      payload, = post_json_rpc(
        method: "tools/call",
        params: {
          "name" => tool_name,
          "arguments" => arguments,
        },
        session_id: session_id
      )

      if payload.key?("error")
        raise SemanticError.new(
          code: "tool_error",
          message: payload.dig("error", "message").to_s.presence || "remote MCP tool failed",
          details: payload.fetch("error"),
          retryable: false
        )
      end

      result = payload["result"]
      raise ProtocolError.new(code: "invalid_json_rpc_response", message: "JSON-RPC response did not include result or error", details: payload) unless result.is_a?(Hash)

      result
    end

    def close_session!(session_id:)
      response = with_http do |http|
        request = Net::HTTP::Delete.new(@uri)
        default_headers("Mcp-Session-Id" => session_id).each { |key, value| request[key] = value }
        http.request(request)
      end

      return true if response.code.to_i == 204
      return false if response.code.to_i == 404

      raise TransportError.new(
        code: "http_error",
        message: "unexpected close response status #{response.code}",
        details: { "status" => response.code.to_i },
        retryable: true
      )
    end

    private

    def notifications_initialized!(session_id:)
      post_json_rpc(
        method: "notifications/initialized",
        params: {},
        session_id: session_id
      )
    end

    def post_json_rpc(method:, params:, session_id: nil)
      response = with_http do |http|
        request = Net::HTTP::Post.new(@uri)
        default_headers(
          {
            "Accept" => "application/json, text/event-stream",
            "Content-Type" => "application/json",
          }.merge(session_id.present? ? { "Mcp-Session-Id" => session_id } : {})
        ).each { |key, value| request[key] = value }
        request.body = JSON.generate(
          "jsonrpc" => "2.0",
          "id" => SecureRandom.uuid,
          "method" => method,
          "params" => params
        )
        http.request(request)
      end

      status = response.code.to_i
      if status == 404 && response.body.to_s.include?("Session not found")
        raise TransportError.new(code: "session_not_found", message: "MCP session was not found", retryable: true)
      end

      unless status.between?(200, 299)
        raise TransportError.new(code: "http_error", message: "unexpected MCP response status #{status}", details: { "status" => status }, retryable: true)
      end

      body = response.body.to_s
      return [{}, normalized_headers(response)] if body.blank?

      payload = JSON.parse(body)
      [payload, normalized_headers(response)]
    rescue JSON::ParserError => error
      raise ProtocolError.new(code: "invalid_json", message: error.message)
    end

    def with_http
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      yield http
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, EOFError, SocketError => error
      raise TransportError.new(code: "connection_error", message: error.message, retryable: true)
    end

    def default_headers(extra_headers = {})
      {
        "User-Agent" => "core-matrix-mcp/1.0",
      }.merge(@headers).merge(extra_headers)
    end

    def normalized_headers(response)
      response.each_header.each_with_object({}) do |(key, value), out|
        out[key.to_s.downcase] = value.to_s
      end
    end

    def header_value(response, key)
      normalized_headers(response).fetch(key.downcase, "")
    end

    def parse_sse_events(body)
      body.split(/\n\n+/).filter_map do |block|
        data_lines = block.each_line.filter_map do |line|
          stripped = line.strip
          next if stripped.empty?
          next if stripped.start_with?(":")
          next stripped.delete_prefix("data: ").strip if stripped.start_with?("data:")

          nil
        end
        next if data_lines.empty?

        JSON.parse(data_lines.join("\n"))
      end
    rescue JSON::ParserError => error
      raise ProtocolError.new(code: "invalid_sse_payload", message: error.message)
    end
  end
end
