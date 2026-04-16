require "test_helper"

class CoreMatrixCLIHTTPClientTest < CoreMatrixCLITestCase
  FakeResponse = Struct.new(:code, :body, :message, keyword_init: true)

  def test_build_request_sends_bearer_token_when_present
    client = CoreMatrixCLI::HTTPClient.new(base_url: "http://example.test", session_token: "sess_123")

    request = client.build_request(:get, "/app_api/session")

    assert_equal "Token token=\"sess_123\"", request["Authorization"]
    assert_equal "application/json", request["Accept"]
  end

  def test_get_parses_successful_json_response
    transport = lambda do |_uri, request, _options|
      assert_equal "GET", request.method
      FakeResponse.new(code: "200", body: "{\"method_id\":\"session_show\"}", message: "OK")
    end
    client = CoreMatrixCLI::HTTPClient.new(base_url: "http://example.test", transport: transport)

    response = client.get("/app_api/session")

    assert_equal({ "method_id" => "session_show" }, response)
  end

  def test_post_json_raises_unauthorized_error_on_401
    transport = lambda do |_uri, request, _options|
      assert_equal "POST", request.method
      FakeResponse.new(code: "401", body: "{\"error\":\"invalid email or password\"}", message: "Unauthorized")
    end
    client = CoreMatrixCLI::HTTPClient.new(base_url: "http://example.test", transport: transport)

    error = assert_raises(CoreMatrixCLI::HTTPClient::UnauthorizedError) do
      client.post("/app_api/session", body: { email: "admin@example.com", password: "wrong" })
    end

    assert_equal 401, error.status
    assert_equal({ "error" => "invalid email or password" }, error.payload)
  end

  def test_patch_json_raises_unprocessable_entity_error_on_422
    transport = lambda do |_uri, request, _options|
      assert_equal "PATCH", request.method
      FakeResponse.new(code: "422", body: "{\"error\":\"webhook base url must be http or https\"}", message: "Unprocessable Entity")
    end
    client = CoreMatrixCLI::HTTPClient.new(base_url: "http://example.test", session_token: "sess_123", transport: transport)

    error = assert_raises(CoreMatrixCLI::HTTPClient::UnprocessableEntityError) do
      client.patch("/app_api/workspace_agents/wa_123/ingress_bindings/ib_123", body: { channel_connector: {} })
    end

    assert_equal 422, error.status
    assert_equal({ "error" => "webhook base url must be http or https" }, error.payload)
  end
end
