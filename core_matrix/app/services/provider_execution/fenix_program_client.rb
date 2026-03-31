require "json"
require "net/http"
require "uri"

module ProviderExecution
  class FenixProgramClient
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

    class NetHttpTransport
      def initialize(open_timeout:, read_timeout:)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def call(uri:, method:, headers:, body:)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout

        request_class =
          case method.to_sym
          when :post
            Net::HTTP::Post
          else
            raise ArgumentError, "unsupported fenix transport method: #{method}"
          end

        request = request_class.new(uri)
        headers.each { |key, value| request[key] = value }
        request.body = body
        http.request(request)
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, EOFError, SocketError => error
        raise TransportError.new(code: "connection_error", message: error.message, retryable: true)
      end
    end

    def initialize(agent_deployment:, transport: nil, open_timeout: 5, read_timeout: 30)
      @agent_deployment = agent_deployment
      @endpoint_metadata = agent_deployment.endpoint_metadata.deep_stringify_keys
      @transport = transport || NetHttpTransport.new(open_timeout:, read_timeout:)
    end

    def prepare_round(body:)
      post_json(path: endpoint_metadata.fetch("prepare_round_path"), body:)
    end

    def execute_program_tool(body:)
      post_json(
        path: endpoint_metadata.fetch("execute_program_tool_path"),
        body:,
        allow_structured_failure: true
      )
    end

    private

    attr_reader :endpoint_metadata

    def post_json(path:, body:, allow_structured_failure: false)
      response = @transport.call(
        uri: request_uri(path),
        method: :post,
        headers: default_headers,
        body: JSON.generate(body)
      )
      status = response.code.to_i
      parsed = parse_json_object(response.body.to_s, path:)

      if allow_structured_failure && status >= 400 && structured_failure_payload?(parsed)
        return parsed
      end

      unless status.between?(200, 299)
        raise TransportError.new(
          code: "http_error",
          message: "unexpected Fenix response status #{status}",
          details: { "status" => status, "path" => path },
          retryable: status >= 500
        )
      end

      parsed
    end

    def parse_json_object(payload, path:)
      return {} if payload.blank?

      parsed = JSON.parse(payload)
      raise ProtocolError.new(code: "invalid_payload", message: "Fenix response must be a JSON object", details: { "path" => path }) unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError => error
      raise ProtocolError.new(code: "invalid_json", message: error.message, details: { "path" => path })
    end

    def structured_failure_payload?(parsed)
      parsed["status"] == "failed" && parsed["error"].is_a?(Hash)
    end

    def request_uri(path)
      URI.join("#{endpoint_metadata.fetch("base_url").to_s.chomp("/")}/", path.to_s.delete_prefix("/"))
    rescue URI::InvalidURIError => error
      raise ProtocolError.new(code: "invalid_endpoint_metadata", message: error.message, details: { "path" => path })
    end

    def default_headers
      {
        "Accept" => "application/json",
        "Content-Type" => "application/json",
        "User-Agent" => "core-matrix-fenix/1.0",
      }
    end
  end
end
