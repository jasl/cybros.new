require "json"
require "time"
require "webrick"

class FakeCoreMatrixServer
  class RouterServlet < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, handler)
      super(server)
      @handler = handler
    end

    def service(request, response)
      @handler.call(request, response)
    end
  end

  class State
    attr_accessor :bootstrap_state, :installation_name, :session_token, :operator_email,
      :operator_display_name, :workspace_id, :workspace_name, :workspace_agent_id,
      :codex_authorization_status_sequence, :codex_authorization_poll_sequence,
      :codex_current_status, :weixin_status_sequence
    attr_reader :authorized_request_tokens, :ingress_bindings

    def initialize
      @bootstrap_state = "bootstrapped"
      @installation_name = "Primary Installation"
      @session_token = "sess_contract_123"
      @operator_email = "admin@example.com"
      @operator_display_name = "Primary Admin"
      @workspace_id = "ws_contract_123"
      @workspace_name = "Primary Workspace"
      @workspace_agent_id = "wa_contract_123"
      @codex_authorization_status_sequence = []
      @codex_authorization_poll_sequence = []
      @codex_current_status = "missing"
      @weixin_status_sequence = []
      @connector_payloads = {}
      @authorized_request_tokens = []
      @ingress_bindings = {}
      @next_ingress_binding_sequence = 0
    end

    def store_connector_payload(platform, payload)
      @connector_payloads[platform] = payload
    end

    def connector_payload_for(platform)
      @connector_payloads.fetch(platform, {})
    end

    def next_ingress_binding(platform)
      @next_ingress_binding_sequence += 1
      ingress_binding_id = "ib_#{platform}_#{@next_ingress_binding_sequence}"
      public_ingress_id = "pub_#{platform}_#{@next_ingress_binding_sequence}"

      @ingress_bindings[ingress_binding_id] = {
        "ingress_binding_id" => ingress_binding_id,
        "platform" => platform,
        "public_ingress_id" => public_ingress_id,
      }
    end

    def next_codex_status
      next_status = @codex_authorization_status_sequence.shift
      @codex_current_status = next_status if next_status
      @codex_current_status
    end

    def next_codex_poll_status
      next_status = @codex_authorization_poll_sequence.shift
      @codex_current_status = next_status if next_status
      @codex_current_status
    end

    def next_weixin_status
      next_status = @weixin_status_sequence.shift
      @last_weixin_status = next_status if next_status
      @last_weixin_status || { "login_state" => "pending" }
    end
  end

  attr_reader :state

  def initialize
    @state = State.new
    yield @state if block_given?
  end

  def start
    @server = WEBrick::HTTPServer.new(
      Port: 0,
      BindAddress: "127.0.0.1",
      AccessLog: [],
      Logger: WEBrick::Log.new(File::NULL)
    )
    @server.mount("/", RouterServlet, method(:handle))
    @thread = Thread.new { @server.start }
    sleep(0.05)
  end

  def shutdown
    @server&.shutdown
    @thread&.join
  end

  def base_url
    "http://127.0.0.1:#{@server.listeners.first.addr[1]}"
  end

  private

  def handle(request, response)
    return if dispatch_public_request(request, response)
    return unless authenticate!(request, response)
    return if dispatch_authenticated_request(request, response)

    respond_json(response, 404, { error: "not found" })
  end

  def dispatch_public_request(request, response)
    if request.request_method == "GET" && request.path == "/app_api/bootstrap/status"
      respond_json(
        response,
        200,
        {
          method_id: "bootstrap_status",
          bootstrap_state: state.bootstrap_state,
          installation: state.bootstrap_state == "bootstrapped" ? installation_payload : nil,
        }
      )
      return true
    end

    if request.request_method == "POST" && request.path == "/app_api/bootstrap"
      body = request_body(request)
      state.bootstrap_state = "bootstrapped"
      state.installation_name = body.fetch("name")
      state.operator_email = body.fetch("email")
      state.operator_display_name = body.fetch("display_name")
      respond_json(response, 201, bootstrap_session_payload)
      return true
    end

    if request.request_method == "POST" && request.path == "/app_api/session"
      body = request_body(request)
      state.operator_email = body.fetch("email")
      respond_json(response, 201, authenticated_session_payload)
      return true
    end

    false
  end

  def dispatch_authenticated_request(request, response)
    if request.request_method == "GET" && request.path == "/app_api/session"
      respond_json(response, 200, authenticated_session_payload(method_id: "session_show", include_session_token: false))
      return true
    end

    if request.request_method == "DELETE" && request.path == "/app_api/session"
      respond_json(response, 200, authenticated_session_payload(method_id: "session_destroy", include_session_token: false))
      return true
    end

    if request.request_method == "GET" && request.path == "/app_api/workspaces"
      respond_json(
        response,
        200,
        {
          method_id: "workspace_list",
          workspaces: [workspace_payload],
        }
      )
      return true
    end

    if request.request_method == "GET" && request.path == "/app_api/admin/llm_providers/codex_subscription"
      codex_status = state.codex_current_status
      respond_json(
        response,
        200,
        {
          method_id: "admin_llm_provider_show",
          llm_provider: {
            provider_handle: "codex_subscription",
            configured: codex_status != "missing",
            usable: codex_status == "authorized",
            reauthorization_required: codex_status == "reauthorization_required",
          },
        }
      )
      return true
    end

    if request.request_method == "POST" && request.path == "/app_api/admin/llm_providers/codex_subscription/authorization"
      state.codex_current_status = "pending"
      respond_json(
        response,
        200,
        {
          method_id: "admin_codex_subscription_authorization_create",
          authorization: {
            provider_handle: "codex_subscription",
            status: "pending",
            verification_uri: "https://auth.openai.com/codex/device",
            user_code: "ABCD-EFGH",
            poll_interval_seconds: 0,
            expires_at: (Time.now + 900).utc.iso8601(6),
          },
        }
      )
      return true
    end

    if request.request_method == "POST" && request.path == "/app_api/admin/llm_providers/codex_subscription/authorization/poll"
      respond_json(
        response,
        200,
        {
          method_id: "admin_codex_subscription_authorization_poll",
          authorization: {
            provider_handle: "codex_subscription",
            status: state.next_codex_poll_status,
          },
        }
      )
      return true
    end

    if request.request_method == "GET" && request.path == "/app_api/admin/llm_providers/codex_subscription/authorization"
      respond_json(
        response,
        200,
        {
          method_id: "admin_codex_subscription_authorization_show",
          authorization: {
            provider_handle: "codex_subscription",
            status: state.next_codex_status,
            verification_uri: "https://auth.openai.com/codex/device",
            user_code: "ABCD-EFGH",
          },
        }
      )
      return true
    end

    if request.request_method == "DELETE" && request.path == "/app_api/admin/llm_providers/codex_subscription/authorization"
      state.codex_current_status = "missing"
      respond_json(
        response,
        200,
        {
          method_id: "admin_codex_subscription_authorization_destroy",
          authorization: {
            provider_handle: "codex_subscription",
            status: "missing",
          },
        }
      )
      return true
    end

    if request.request_method == "POST" && request.path.match?(%r{\A/app_api/workspace_agents/[^/]+/ingress_bindings\z})
      body = request_body(request)
      ingress_binding = state.next_ingress_binding(body.fetch("platform"))
      respond_json(
        response,
        201,
        {
          method_id: "ingress_binding_create",
          ingress_binding: {
            ingress_binding_id: ingress_binding.fetch("ingress_binding_id"),
            setup: create_setup_payload(ingress_binding),
          },
        }
      )
      return true
    end

    if request.request_method == "PATCH" && request.path.match?(%r{\A/app_api/workspace_agents/[^/]+/ingress_bindings/[^/]+\z})
      body = request_body(request)
      ingress_binding_id = request.path.split("/").last
      ingress_binding = state.ingress_bindings.fetch(ingress_binding_id)
      state.store_connector_payload(ingress_binding.fetch("platform"), body.fetch("channel_connector"))

      respond_json(
        response,
        200,
        {
          method_id: "ingress_binding_update",
          ingress_binding: {
            ingress_binding_id: ingress_binding_id,
            setup: update_setup_payload(ingress_binding),
          },
        }
      )
      return true
    end

    if request.request_method == "GET" && request.path.match?(%r{\A/app_api/workspace_agents/[^/]+/ingress_bindings/[^/]+\z})
      ingress_binding_id = request.path.split("/").last
      ingress_binding = state.ingress_bindings.fetch(ingress_binding_id)
      configured = configured_ingress_binding?(ingress_binding)

      respond_json(
        response,
        200,
        {
          method_id: "ingress_binding_show",
          ingress_binding: {
            ingress_binding_id: ingress_binding_id,
            channel_connector: {
              configured: configured,
            },
          },
        }
      )
      return true
    end

    if request.request_method == "POST" && request.path.match?(%r{\A/app_api/workspace_agents/[^/]+/ingress_bindings/[^/]+/weixin/start_login\z})
      respond_json(
        response,
        200,
        {
          method_id: "ingress_binding_weixin_start_login",
          weixin: {
            login_state: "pending",
          },
        }
      )
      return true
    end

    if request.request_method == "GET" && request.path.match?(%r{\A/app_api/workspace_agents/[^/]+/ingress_bindings/[^/]+/weixin/login_status\z})
      respond_json(
        response,
        200,
        {
          method_id: "ingress_binding_weixin_login_status",
          weixin: state.next_weixin_status,
        }
      )
      return true
    end

    false
  end

  def authenticate!(request, response)
    expected_header = %(Token token="#{state.session_token}")
    authorization_header = request["Authorization"]
    return record_authorized_request(authorization_header) if authorization_header == expected_header

    respond_json(response, 401, { error: "unauthorized" })
    false
  end

  def record_authorized_request(authorization_header)
    state.authorized_request_tokens << authorization_header[%r{token="([^"]+)"}, 1]
    true
  end

  def bootstrap_session_payload
    authenticated_session_payload(
      method_id: "bootstrap_create",
      include_session_token: true,
      include_workspace_context: true
    )
  end

  def authenticated_session_payload(method_id: "session_create", include_session_token: true, include_workspace_context: false)
    payload = {
      method_id: method_id,
      session_token: include_session_token ? state.session_token : nil,
      user: {
        user_id: "usr_contract_123",
        display_name: state.operator_display_name,
        role: "admin",
        email: state.operator_email,
      },
      installation: installation_payload,
      session: {
        session_id: "ses_contract_123",
        expires_at: "2030-01-01T00:00:00.000000Z",
      },
    }

    if include_workspace_context
      payload[:workspace] = workspace_payload
      payload[:workspace_agent] = workspace_agent_payload
    end

    payload.compact
  end

  def installation_payload
    {
      name: state.installation_name,
      bootstrap_state: state.bootstrap_state,
    }
  end

  def workspace_payload
    {
      workspace_id: state.workspace_id,
      name: state.workspace_name,
      is_default: true,
      privacy: "private",
      workspace_agents: [workspace_agent_payload],
    }
  end

  def workspace_agent_payload
    {
      workspace_agent_id: state.workspace_agent_id,
      workspace_id: state.workspace_id,
      agent_id: "agt_contract_123",
      lifecycle_state: "active",
    }
  end

  def create_setup_payload(ingress_binding)
    case ingress_binding.fetch("platform")
    when "telegram"
      {
        poller_binding_id: ingress_binding.fetch("public_ingress_id"),
      }
    when "telegram_webhook"
      {
        webhook_path: "/ingress_api/telegram/bindings/#{ingress_binding.fetch("public_ingress_id")}/updates",
      }
    else
      {}
    end
  end

  def update_setup_payload(ingress_binding)
    case ingress_binding.fetch("platform")
    when "telegram"
      {
        poller_binding_id: ingress_binding.fetch("public_ingress_id"),
      }
    when "telegram_webhook"
      {
        webhook_path: "/ingress_api/telegram/bindings/#{ingress_binding.fetch("public_ingress_id")}/updates",
        webhook_secret_token: "secret_#{ingress_binding.fetch("ingress_binding_id")}",
      }
    else
      {}
    end
  end

  def configured_ingress_binding?(ingress_binding)
    connector_payload = state.connector_payload_for(ingress_binding.fetch("platform"))

    case ingress_binding.fetch("platform")
    when "telegram"
      connector_payload.dig("credential_ref_payload", "bot_token").to_s.strip != ""
    when "telegram_webhook"
      connector_payload.dig("credential_ref_payload", "bot_token").to_s.strip != "" &&
        connector_payload.dig("config_payload", "webhook_base_url").to_s.strip != ""
    else
      true
    end
  end

  def request_body(request)
    return {} if request.body.to_s.strip.empty?

    JSON.parse(request.body)
  end

  def respond_json(response, status, payload)
    response.status = status
    response["Content-Type"] = "application/json"
    response.body = JSON.generate(payload)
  end
end
