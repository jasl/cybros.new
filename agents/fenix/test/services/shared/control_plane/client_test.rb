require "test_helper"
require "net/http"

class Shared::ControlPlane::ClientTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body, keyword_init: true)

  test "poll and report stay on the agent control plane" do
    requests = []
    mailbox_items = nil

    with_captured_requests(requests) do
      client = Shared::ControlPlane::Client.new(
        base_url: "https://core-matrix.example.test",
        agent_connection_credential: "secret"
      )

      mailbox_items = client.poll(limit: 5)
      client.report!(payload: { "method_id" => "agent_completed" })
    end

    assert_equal %w[agent-1], mailbox_items.map { |item| item.fetch("item_id") }
    assert_equal [
      "POST /agent_api/control/poll",
      "POST /agent_api/control/report",
    ], requests.map { |entry| "#{entry.fetch(:method)} #{entry.fetch(:path)}" }
    assert_equal [
      %(Token token="secret"),
      %(Token token="secret"),
    ], requests.map { |entry| entry.fetch(:authorization) }
  end

  test "connection_context exports the settings needed by queued mailbox execution" do
    client = Shared::ControlPlane::Client.new(
      base_url: "https://core-matrix.example.test",
      agent_connection_credential: "secret"
    )

    assert_equal(
      {
        "base_url" => "https://core-matrix.example.test",
        "agent_connection_credential" => "secret",
        "open_timeout" => Shared::ControlPlane::Client::DEFAULT_OPEN_TIMEOUT,
        "read_timeout" => Shared::ControlPlane::Client::DEFAULT_READ_TIMEOUT,
        "write_timeout" => Shared::ControlPlane::Client::DEFAULT_WRITE_TIMEOUT,
      },
      client.connection_context
    )
  end

  test "register omits authorization while heartbeat uses the agent credential" do
    requests = []

    with_captured_requests(requests) do
      client = Shared::ControlPlane::Client.new(
        base_url: "https://core-matrix.example.test",
        agent_connection_credential: "secret"
      )

      client.register!(
        pairing_token: "pairing-token",
        endpoint_metadata: { "transport" => "http", "base_url" => "http://fenix.example.test:3101", "runtime_manifest_path" => "/runtime/manifest" },
        definition_package: {
          "program_manifest_fingerprint" => "bundled-fenix-release-0.1.0",
          "prompt_pack_ref" => "fenix/default",
          "prompt_pack_fingerprint" => "prompt-pack-a",
          "protocol_version" => "agent-runtime/2026-04-01",
          "sdk_version" => "fenix-0.1.0",
          "protocol_methods" => [],
          "tool_contract" => [],
          "canonical_config_schema" => {},
          "conversation_override_schema" => {},
          "workspace_agent_settings_schema" => {},
          "default_workspace_agent_settings" => {},
          "default_canonical_config" => {},
          "reflected_surface" => {},
        }
      )
      client.heartbeat!(health_status: "healthy", auto_resume_eligible: true)
    end

    register_request = requests.fetch(0)
    heartbeat_request = requests.fetch(1)

    assert_equal "/agent_api/registrations", register_request.fetch(:path)
    assert_nil register_request.fetch(:authorization)
    assert_equal "pairing-token", register_request.fetch(:json_body).fetch("pairing_token")
    assert_equal "bundled-fenix-release-0.1.0", register_request.dig(:json_body, "definition_package", "program_manifest_fingerprint")

    assert_equal "/agent_api/heartbeats", heartbeat_request.fetch(:path)
    assert_equal %(Token token="secret"), heartbeat_request.fetch(:authorization)
    assert_equal "healthy", heartbeat_request.fetch(:json_body).fetch("health_status")
  end

  test "health and capabilities endpoints use the agent credential" do
    requests = []

    with_captured_requests(requests) do
      client = Shared::ControlPlane::Client.new(
        base_url: "https://core-matrix.example.test",
        agent_connection_credential: "secret"
      )

      client.health
      client.capabilities_refresh
      client.capabilities_handshake!(
        definition_package: {
          "program_manifest_fingerprint" => "bundled-fenix-release-0.1.0",
          "prompt_pack_ref" => "fenix/default",
          "prompt_pack_fingerprint" => "prompt-pack-a",
          "protocol_version" => "agent-runtime/2026-04-01",
          "sdk_version" => "fenix-0.1.0",
          "protocol_methods" => [{ "method_id" => "agent_completed" }],
          "tool_contract" => [{ "tool_name" => "compact_context" }],
          "canonical_config_schema" => {},
          "conversation_override_schema" => {},
          "workspace_agent_settings_schema" => {},
          "default_workspace_agent_settings" => {},
          "default_canonical_config" => {},
          "reflected_surface" => {},
        }
      )
    end

    assert_equal [
      "GET /agent_api/health",
      "GET /agent_api/capabilities",
      "POST /agent_api/capabilities",
    ], requests.map { |entry| "#{entry.fetch(:method)} #{entry.fetch(:path)}" }
    assert_equal [
      %(Token token="secret"),
      %(Token token="secret"),
      %(Token token="secret"),
    ], requests.map { |entry| entry.fetch(:authorization) }
    assert_equal "bundled-fenix-release-0.1.0", requests.fetch(2).dig(:json_body, "definition_package", "program_manifest_fingerprint")
  end

  test "input token counting posts to the advisory responses endpoint with the agent credential" do
    requests = []

    with_captured_requests(requests) do
      client = Shared::ControlPlane::Client.new(
        base_url: "https://core-matrix.example.test",
        agent_connection_credential: "secret"
      )

      client.input_tokens!(
        provider_handle: "dev",
        model_ref: "mock-model",
        input: [
          {
            role: "user",
            content: "Count this provider-visible input.",
          },
        ]
      )
    end

    assert_equal ["POST /agent_api/responses/input_tokens"], requests.map { |entry| "#{entry.fetch(:method)} #{entry.fetch(:path)}" }
    assert_equal %(Token token="secret"), requests.first.fetch(:authorization)
    assert_equal "dev", requests.first.dig(:json_body, "provider_handle")
    assert_equal "mock-model", requests.first.dig(:json_body, "model_ref")
  end

  test "report treats stale 409 responses as idempotent replays" do
    requests = []

    with_captured_requests(
      requests,
      responses: {
        "/agent_api/control/report" => { code: "409", body: { "result" => "stale", "mailbox_items" => [] } },
      }
    ) do
      client = Shared::ControlPlane::Client.new(
        base_url: "https://core-matrix.example.test",
        agent_connection_credential: "secret"
      )

      response = client.report!(payload: { "method_id" => "agent_completed" })

      assert_equal "stale", response.fetch("result")
    end

    assert_equal ["POST /agent_api/control/report"], requests.map { |entry| "#{entry.fetch(:method)} #{entry.fetch(:path)}" }
  end

  private

  def with_captured_requests(requests, responses: {})
    original_start = Net::HTTP.method(:start)
    resolver = method(:response_for)

    Net::HTTP.singleton_class.define_method(:start) do |_host, _port, **_kwargs, &block|
      http = Object.new
      http.define_singleton_method(:request) do |request|
        requests << {
          method: request.method,
          path: request.path,
          authorization: request["Authorization"],
          json_body: request.body.present? ? JSON.parse(request.body) : nil,
        }

        response = responses.fetch(request.path, { code: "200", body: resolver.call(request.path) })

        Response.new(code: response.fetch(:code), body: JSON.generate(response.fetch(:body)))
      end

      block.call(http)
    end

    yield
  ensure
    Net::HTTP.singleton_class.define_method(:start, original_start)
  end

  def response_for(path)
    case path
    when "/agent_api/control/poll"
      { "mailbox_items" => [{ "item_id" => "agent-1", "control_plane" => "agent" }] }
    else
      { "result" => "accepted" }
    end
  end
end
