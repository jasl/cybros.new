require "test_helper"

class CoreMatrixAPITest < CoreMatrixCLITestCase
  FakeResponse = Struct.new(:code, :body, :message, keyword_init: true)

  def test_login_posts_json_and_parses_successful_response
    transport = lambda do |uri, request, options|
      assert_equal URI("https://core.example.test/app_api/session"), uri
      assert_equal "POST", request.method
      assert_equal "application/json", request["Content-Type"]
      assert_equal "application/json", request["Accept"]
      assert_equal({ "email" => "admin@example.com", "password" => "Password123!" }, JSON.parse(request.body))
      assert_equal 5, options.fetch(:open_timeout)
      assert_equal 30, options.fetch(:read_timeout)

      FakeResponse.new(code: "200", body: "{\"session_token\":\"sess_123\"}", message: "OK")
    end

    api = CoreMatrixCLI::CoreMatrixAPI.new(base_url: "https://core.example.test", transport: transport)

    assert_equal({ "session_token" => "sess_123" }, api.login(email: "admin@example.com", password: "Password123!"))
  end

  def test_current_session_sends_authorization_header
    transport = lambda do |_uri, request, _options|
      assert_equal "Token token=\"sess_123\"", request["Authorization"]

      FakeResponse.new(code: "200", body: "{\"user\":{\"email\":\"admin@example.com\"}}", message: "OK")
    end

    api = CoreMatrixCLI::CoreMatrixAPI.new(base_url: "https://core.example.test", session_token: "sess_123", transport: transport)

    assert_equal "admin@example.com", api.current_session.dig("user", "email")
  end

  def test_update_ingress_binding_patches_expected_endpoint
    transport = lambda do |uri, request, _options|
      assert_equal URI("https://core.example.test/app_api/workspace_agents/wa_123/ingress_bindings/ib_123"), uri
      assert_equal "PATCH", request.method
      assert_equal(
        {
          "channel_connector" => { "type" => "telegram", "bot_token" => "123:abc" },
          "reissue_setup_secret" => true,
        },
        JSON.parse(request.body)
      )

      FakeResponse.new(code: "200", body: "{\"ingress_binding\":{\"ingress_binding_id\":\"ib_123\"}}", message: "OK")
    end

    api = CoreMatrixCLI::CoreMatrixAPI.new(base_url: "https://core.example.test", session_token: "sess_123", transport: transport)

    payload = api.update_ingress_binding(
      workspace_agent_id: "wa_123",
      ingress_binding_id: "ib_123",
      channel_connector: { type: "telegram", bot_token: "123:abc" },
      reissue_setup_secret: true
    )

    assert_equal "ib_123", payload.dig("ingress_binding", "ingress_binding_id")
  end

  def test_raises_unauthorized_error_on_401
    transport = lambda do |_uri, _request, _options|
      FakeResponse.new(code: "401", body: "{\"error\":\"invalid email or password\"}", message: "Unauthorized")
    end
    api = CoreMatrixCLI::CoreMatrixAPI.new(base_url: "https://core.example.test", transport: transport)

    error = assert_raises(CoreMatrixCLI::Errors::UnauthorizedError) do
      api.login(email: "admin@example.com", password: "wrong")
    end

    assert_equal 401, error.status
    assert_equal({ "error" => "invalid email or password" }, error.payload)
  end

  def test_raises_not_found_error_on_404
    transport = lambda do |_uri, _request, _options|
      FakeResponse.new(code: "404", body: "{\"error\":\"not found\"}", message: "Not Found")
    end
    api = CoreMatrixCLI::CoreMatrixAPI.new(base_url: "https://core.example.test", session_token: "sess_123", transport: transport)

    error = assert_raises(CoreMatrixCLI::Errors::NotFoundError) do
      api.show_ingress_binding(workspace_agent_id: "wa_123", ingress_binding_id: "ib_missing")
    end

    assert_equal 404, error.status
    assert_equal({ "error" => "not found" }, error.payload)
  end

  def test_raises_unprocessable_entity_error_on_422
    transport = lambda do |_uri, _request, _options|
      FakeResponse.new(code: "422", body: "{\"error\":\"webhook base url must be http or https\"}", message: "Unprocessable Entity")
    end
    api = CoreMatrixCLI::CoreMatrixAPI.new(base_url: "https://core.example.test", session_token: "sess_123", transport: transport)

    error = assert_raises(CoreMatrixCLI::Errors::UnprocessableEntityError) do
      api.update_ingress_binding(
        workspace_agent_id: "wa_123",
        ingress_binding_id: "ib_123",
        channel_connector: { webhook_base_url: "ftp://bad.example.test" }
      )
    end

    assert_equal 422, error.status
    assert_equal({ "error" => "webhook base url must be http or https" }, error.payload)
  end

  def test_raises_server_error_on_5xx
    transport = lambda do |_uri, _request, _options|
      FakeResponse.new(code: "500", body: "{\"error\":\"server exploded\"}", message: "Internal Server Error")
    end
    api = CoreMatrixCLI::CoreMatrixAPI.new(base_url: "https://core.example.test", session_token: "sess_123", transport: transport)

    error = assert_raises(CoreMatrixCLI::Errors::ServerError) do
      api.list_workspaces
    end

    assert_equal 500, error.status
    assert_equal({ "error" => "server exploded" }, error.payload)
  end

  def test_wraps_transport_failures
    transport = lambda do |_uri, _request, _options|
      raise IOError, "connection reset by peer"
    end
    api = CoreMatrixCLI::CoreMatrixAPI.new(base_url: "https://core.example.test", transport: transport)

    error = assert_raises(CoreMatrixCLI::Errors::TransportError) do
      api.bootstrap_status
    end

    assert_includes error.message, "connection reset by peer"
  end
end
