module CoreMatrixCLI
  class HTTPClient
    Error = Class.new(StandardError)
    TransportError = Class.new(Error)

    class ResponseError < Error
      attr_reader :status, :payload

      def initialize(message, status:, payload:)
        super(message)
        @status = status
        @payload = payload
      end
    end

    UnauthorizedError = Class.new(ResponseError)
    NotFoundError = Class.new(ResponseError)
    UnprocessableEntityError = Class.new(ResponseError)
    ServerError = Class.new(ResponseError)

    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_READ_TIMEOUT = 30

    def initialize(base_url:, session_token: nil, open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT, transport: nil)
      @base_url = base_url
      @session_token = session_token
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @transport = transport || method(:perform_request)
    end

    attr_reader :session_token

    def with_session_token(session_token)
      self.class.new(
        base_url: @base_url,
        session_token: session_token,
        open_timeout: @open_timeout,
        read_timeout: @read_timeout,
        transport: @transport
      )
    end

    def get(path, headers: {})
      request(:get, path, headers: headers)
    end

    def post(path, body: nil, headers: {})
      request(:post, path, body: body, headers: headers)
    end

    def patch(path, body: nil, headers: {})
      request(:patch, path, body: body, headers: headers)
    end

    def delete(path, headers: {})
      request(:delete, path, headers: headers)
    end

    def build_request(method, path, body: nil, headers: {})
      uri = resolve_uri(path)
      request_class = request_class_for(method)
      request = request_class.new(uri)
      request["Accept"] = "application/json"
      request["Authorization"] = ActionController::HttpAuthentication::Token.encode_credentials(@session_token) if @session_token.to_s.strip != ""
      headers.each { |key, value| request[key] = value }

      if body
        request["Content-Type"] ||= "application/json"
        request.body = JSON.generate(body)
      end

      request
    end

    private

    def request(method, path, body: nil, headers: {})
      uri = resolve_uri(path)
      request = build_request(method, path, body: body, headers: headers)
      response = @transport.call(uri, request, open_timeout: @open_timeout, read_timeout: @read_timeout)
      handle_response(response)
    rescue ResponseError
      raise
    rescue StandardError => error
      raise TransportError, error.message
    end

    def resolve_uri(path)
      URI.join(normalized_base_url, path)
    end

    def normalized_base_url
      @base_url.end_with?("/") ? @base_url : "#{@base_url}/"
    end

    def request_class_for(method)
      case method.to_sym
      when :get then Net::HTTP::Get
      when :post then Net::HTTP::Post
      when :patch then Net::HTTP::Patch
      when :delete then Net::HTTP::Delete
      else
        raise ArgumentError, "unsupported http method: #{method}"
      end
    end

    def perform_request(uri, request, open_timeout:, read_timeout:)
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: open_timeout,
        read_timeout: read_timeout
      ) do |http|
        http.request(request)
      end
    end

    def handle_response(response)
      payload = parse_payload(response.body)
      status = response.code.to_i

      return payload if status.between?(200, 299)

      error_message = payload.is_a?(Hash) ? payload["error"] || response.message : response.message

      case status
      when 401
        raise UnauthorizedError.new(error_message, status: status, payload: payload)
      when 404
        raise NotFoundError.new(error_message, status: status, payload: payload)
      when 422
        raise UnprocessableEntityError.new(error_message, status: status, payload: payload)
      else
        raise ServerError.new(error_message, status: status, payload: payload)
      end
    end

    def parse_payload(body)
      return {} if body.to_s.strip.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      { "raw_body" => body.to_s }
    end
  end
end
