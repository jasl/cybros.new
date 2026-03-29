require "json"
require "socket"

class FakeStreamableHttpMcpServer
  Response = Struct.new(:status, :headers, :body, keyword_init: true)

  attr_reader :base_url, :requests

  def initialize
    @requests = []
    @sessions = {}
    @issued_session_ids = []
    @next_failure = nil
  end

  def start
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @base_url = "http://127.0.0.1:#{@port}/mcp"
    @running = true
    @thread = Thread.new { accept_loop }
    wait_until_ready!
    self
  end

  def shutdown
    @running = false
    @server&.close
    @thread&.join
  end

  def issued_session_ids
    @issued_session_ids.dup
  end

  def fail_next_tool_call_with_session_not_found!
    @next_failure = :session_not_found
  end

  def fail_next_tool_call_with_protocol_error!
    @next_failure = :protocol_error
  end

  def fail_next_tool_call_with_semantic_error!
    @next_failure = :semantic_error
  end

  private

  def accept_loop
    while @running
      begin
        socket = @server.accept
        handle_connection(socket)
      rescue IOError, Errno::EBADF
        break
      end
    end
  end

  def handle_connection(socket)
    request = parse_request(socket)
    return if request.nil?

    @requests << request
    response = route(request)
    socket.write(serialize_response(response))
  ensure
    socket.close unless socket.closed?
  end

  def parse_request(socket)
    request_line = socket.gets
    return if request_line.nil?

    method, path, _http_version = request_line.strip.split(" ", 3)
    headers = {}

    while (line = socket.gets)
      line = line.chomp
      break if line.empty?

      key, value = line.split(":", 2)
      headers[key.downcase] = value.to_s.strip
    end

    body = +""
    content_length = headers["content-length"].to_i
    body << socket.read(content_length).to_s if content_length.positive?

    {
      method: method,
      path: path,
      headers: headers,
      body: body,
    }
  end

  def route(request)
    case request.fetch(:method)
    when "POST" then handle_post(request)
    when "GET" then handle_get(request)
    when "DELETE" then handle_delete(request)
    else
      json_response(405, { error: "method_not_allowed" })
    end
  end

  def handle_post(request)
    payload = JSON.parse(request.fetch(:body))
    method_name = payload.fetch("method")

    case method_name
    when "initialize"
      session_id = "session-#{@issued_session_ids.length + 1}"
      @issued_session_ids << session_id
      @sessions[session_id] = :open

      Response.new(
        status: 200,
        headers: {
          "Content-Type" => "application/json",
          "Mcp-Session-Id" => session_id,
        },
        body: JSON.generate(
          "jsonrpc" => "2.0",
          "id" => payload.fetch("id"),
          "result" => {
            "protocolVersion" => "2024-11-05",
            "serverInfo" => { "name" => "fake-mcp", "version" => "1.0.0" },
            "capabilities" => { "tools" => {} },
          }
        )
      )
    when "notifications/initialized"
      Response.new(status: 202, headers: { "Content-Type" => "application/json" }, body: "")
    when "tools/call"
      session_id = request.dig(:headers, "mcp-session-id").to_s
      return session_not_found_response if session_id.empty? || @sessions[session_id] != :open

      case consume_failure_mode
      when :session_not_found
        @sessions.delete(session_id)
        session_not_found_response
      when :protocol_error
        json_response(200, "jsonrpc" => "2.0", "id" => payload.fetch("id"))
      when :semantic_error
        json_response(
          200,
          "jsonrpc" => "2.0",
          "id" => payload.fetch("id"),
          "error" => {
            "code" => -32_001,
            "message" => "remote tool failed",
          }
        )
      else
        message = payload.dig("params", "arguments", "message")
        json_response(
          200,
          "jsonrpc" => "2.0",
          "id" => payload.fetch("id"),
          "result" => {
            "content" => [
              { "type" => "text", "text" => "echo: #{message}" },
            ],
          }
        )
      end
    else
      json_response(404, { error: "unknown_method" })
    end
  end

  def handle_get(request)
    session_id = request.dig(:headers, "mcp-session-id").to_s
    return session_not_found_response if session_id.empty? || @sessions[session_id] != :open

    Response.new(
      status: 200,
      headers: { "Content-Type" => "text/event-stream" },
      body: <<~SSE
        : keepalive

        data: #{JSON.generate("jsonrpc" => "2.0", "method" => "notifications/ready", "params" => { "sessionId" => session_id })}

      SSE
    )
  end

  def handle_delete(request)
    session_id = request.dig(:headers, "mcp-session-id").to_s
    return session_not_found_response if session_id.empty? || @sessions.delete(session_id).nil?

    Response.new(status: 204, headers: {}, body: "")
  end

  def json_response(status, payload)
    Response.new(
      status: status,
      headers: { "Content-Type" => "application/json" },
      body: JSON.generate(payload)
    )
  end

  def session_not_found_response
    json_response(
      404,
      "jsonrpc" => "2.0",
      "error" => {
        "code" => -32_000,
        "message" => "Session not found",
      }
    )
  end

  def serialize_response(response)
    reason = {
      200 => "OK",
      202 => "Accepted",
      204 => "No Content",
      404 => "Not Found",
      405 => "Method Not Allowed",
    }.fetch(response.status, "OK")

    headers = response.headers.merge(
      "Content-Length" => response.body.bytesize.to_s,
      "Connection" => "close"
    )

    +"HTTP/1.1 #{response.status} #{reason}\r\n" +
      headers.map { |key, value| "#{key}: #{value}\r\n" }.join +
      "\r\n" +
      response.body
  end

  def wait_until_ready!
    deadline = Time.now + 5

    loop do
      TCPSocket.new("127.0.0.1", @port).close
      return
    rescue Errno::ECONNREFUSED
      raise "fake MCP server did not start" if Time.now >= deadline

      sleep 0.05
    end
  end

  def consume_failure_mode
    failure = @next_failure
    @next_failure = nil
    failure
  end
end
