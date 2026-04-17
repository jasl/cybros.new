require "json"
require "net/http"
require "uri"

module CoreMatrixCLI
  class CoreMatrixAPI
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

    def bootstrap_status
      get("/app_api/bootstrap/status")
    end

    def bootstrap(attributes)
      post("/app_api/bootstrap", body: attributes)
    end

    def login(email:, password:)
      post(
        "/app_api/session",
        body: {
          email: email,
          password: password,
        }
      )
    end

    def current_session
      get("/app_api/session")
    end

    def logout
      delete("/app_api/session")
    end

    def installation_status
      get("/app_api/admin/installation")
    end

    def list_workspaces
      get("/app_api/workspaces")
    end

    def create_workspace(name:, privacy: "private", is_default: false)
      post(
        "/app_api/workspaces",
        body: {
          name: name,
          privacy: privacy,
          is_default: is_default,
        }
      )
    end

    def list_agents
      get("/app_api/agents")
    end

    def attach_workspace_agent(workspace_id:, agent_id:)
      post(
        "/app_api/workspaces/#{workspace_id}/workspace_agents",
        body: { agent_id: agent_id }
      )
    end

    def provider_status(provider_handle)
      get("/app_api/admin/llm_providers/#{provider_handle}")
    end

    def start_codex_authorization
      post("/app_api/admin/llm_providers/codex_subscription/authorization")
    end

    def codex_authorization_status
      get("/app_api/admin/llm_providers/codex_subscription/authorization")
    end

    def poll_codex_authorization
      post("/app_api/admin/llm_providers/codex_subscription/authorization/poll")
    end

    def revoke_codex_authorization
      delete("/app_api/admin/llm_providers/codex_subscription/authorization")
    end

    def create_ingress_binding(workspace_agent_id:, platform:)
      post(
        "/app_api/workspace_agents/#{workspace_agent_id}/ingress_bindings",
        body: { platform: platform }
      )
    end

    def update_ingress_binding(workspace_agent_id:, ingress_binding_id:, channel_connector:, reissue_setup_secret: false)
      patch(
        "/app_api/workspace_agents/#{workspace_agent_id}/ingress_bindings/#{ingress_binding_id}",
        body: {
          channel_connector: channel_connector,
          reissue_setup_secret: reissue_setup_secret,
        }
      )
    end

    def show_ingress_binding(workspace_agent_id:, ingress_binding_id:)
      get("/app_api/workspace_agents/#{workspace_agent_id}/ingress_bindings/#{ingress_binding_id}")
    end

    def start_weixin_login(workspace_agent_id:, ingress_binding_id:)
      post("/app_api/workspace_agents/#{workspace_agent_id}/ingress_bindings/#{ingress_binding_id}/weixin/start_login")
    end

    def weixin_login_status(workspace_agent_id:, ingress_binding_id:)
      get("/app_api/workspace_agents/#{workspace_agent_id}/ingress_bindings/#{ingress_binding_id}/weixin/login_status")
    end

    def build_request(method, path, body: nil, headers: {})
      uri = resolve_uri(path)
      request = request_class_for(method).new(uri)
      request["Accept"] = "application/json"
      request["Authorization"] = encoded_token_credentials(@session_token) if @session_token.to_s.strip != ""
      headers.each { |key, value| request[key] = value }

      if body
        request["Content-Type"] ||= "application/json"
        request.body = JSON.generate(body)
      end

      request
    end

    private

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

    def request(method, path, body: nil, headers: {})
      uri = resolve_uri(path)
      response = @transport.call(
        uri,
        build_request(method, path, body: body, headers: headers),
        open_timeout: @open_timeout,
        read_timeout: @read_timeout
      )
      handle_response(response)
    rescue Errors::ResponseError
      raise
    rescue StandardError => error
      raise Errors::TransportError, error.message
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

    def encoded_token_credentials(token)
      escaped_token = token.to_s.gsub("\\", "\\\\").gsub('"', '\"')
      %(Token token="#{escaped_token}")
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

      message = payload.is_a?(Hash) ? payload["error"] || response.message : response.message

      case status
      when 401
        raise Errors::UnauthorizedError.new(message, status: status, payload: payload)
      when 404
        raise Errors::NotFoundError.new(message, status: status, payload: payload)
      when 422
        raise Errors::UnprocessableEntityError.new(message, status: status, payload: payload)
      else
        raise Errors::ServerError.new(message, status: status, payload: payload)
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
