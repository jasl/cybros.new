require "test_helper"
require "net/http"

class Shared::ControlPlane::ClientTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body, keyword_init: true)

  test "poll and report stay on the execution runtime control plane" do
    requests = []
    mailbox_items = nil

    with_captured_requests(requests) do
      client = Shared::ControlPlane::Client.new(
        base_url: "https://core-matrix.example.test",
        execution_runtime_connection_credential: "execution-secret"
      )

      mailbox_items = client.poll(limit: 5)
      client.report!(payload: { "method_id" => "execution_started" })
    end

    assert_equal %w[runtime-1], mailbox_items.map { |item| item.fetch("item_id") }
    assert_equal [
      "POST /execution_runtime_api/control/poll",
      "POST /execution_runtime_api/control/report",
    ], requests.map { |entry| "#{entry.fetch(:method)} #{entry.fetch(:path)}" }
    assert_equal [
      %(Token token="execution-secret"),
      %(Token token="execution-secret"),
    ], requests.map { |entry| entry.fetch(:authorization) }
  end

  test "connection_context exports the settings needed by queued mailbox execution" do
    client = Shared::ControlPlane::Client.new(
      base_url: "https://core-matrix.example.test",
      execution_runtime_connection_credential: "execution-secret"
    )

    assert_equal(
      {
        "base_url" => "https://core-matrix.example.test",
        "execution_runtime_connection_credential" => "execution-secret",
        "open_timeout" => Shared::ControlPlane::Client::DEFAULT_OPEN_TIMEOUT,
        "read_timeout" => Shared::ControlPlane::Client::DEFAULT_READ_TIMEOUT,
        "write_timeout" => Shared::ControlPlane::Client::DEFAULT_WRITE_TIMEOUT,
      },
      client.connection_context
    )
  end

  test "register omits authorization while runtime endpoints use the execution runtime credential" do
    requests = []

    with_captured_requests(requests) do
      client = Shared::ControlPlane::Client.new(
        base_url: "https://core-matrix.example.test",
        execution_runtime_connection_credential: "execution-secret"
      )

      client.register!(
        pairing_token: "pairing-token",
        endpoint_metadata: { "transport" => "http", "base_url" => "http://nexus.example.test:3101" },
        version_package: {
          "execution_runtime_fingerprint" => "bundled-nexus-environment",
          "kind" => "local",
          "protocol_version" => "agent-runtime/2026-04-01",
          "sdk_version" => "nexus-0.1.0",
          "capability_payload" => { "runtime_foundation" => { "docker_base_project" => "images/nexus" } },
          "tool_catalog" => [{ "tool_name" => "exec_command" }],
          "reflected_host_metadata" => {},
        }
      )
      client.health
    end

    register_request = requests.fetch(0)
    health_request = requests.fetch(1)

    assert_equal "/execution_runtime_api/registrations", register_request.fetch(:path)
    assert_nil register_request.fetch(:authorization)
    assert_equal "pairing-token", register_request.fetch(:json_body).fetch("pairing_token")
    assert_equal "bundled-nexus-environment", register_request.dig(:json_body, "version_package", "execution_runtime_fingerprint")

    assert_equal "/execution_runtime_api/health", health_request.fetch(:path)
    assert_equal %(Token token="execution-secret"), health_request.fetch(:authorization)
  end

  test "health and capabilities endpoints use the execution runtime credential" do
    requests = []

    with_captured_requests(requests) do
      client = Shared::ControlPlane::Client.new(
        base_url: "https://core-matrix.example.test",
        execution_runtime_connection_credential: "execution-secret"
      )

      client.health
      client.capabilities_refresh
      client.capabilities_handshake!(
        version_package: {
          "execution_runtime_fingerprint" => "bundled-nexus-environment",
          "kind" => "local",
          "protocol_version" => "agent-runtime/2026-04-01",
          "sdk_version" => "nexus-0.1.0",
          "capability_payload" => { "runtime_foundation" => { "docker_base_project" => "images/nexus" } },
          "tool_catalog" => [{ "tool_name" => "exec_command" }],
          "reflected_host_metadata" => {},
        }
      )
    end

    assert_equal [
      "GET /execution_runtime_api/health",
      "GET /execution_runtime_api/capabilities",
      "POST /execution_runtime_api/capabilities",
    ], requests.map { |entry| "#{entry.fetch(:method)} #{entry.fetch(:path)}" }
    assert_equal [
      %(Token token="execution-secret"),
      %(Token token="execution-secret"),
      %(Token token="execution-secret"),
    ], requests.map { |entry| entry.fetch(:authorization) }
    assert_equal "images/nexus", requests.fetch(2).dig(:json_body, "version_package", "capability_payload", "runtime_foundation", "docker_base_project")
  end

  test "report treats stale 409 responses as idempotent replays" do
    requests = []

    with_captured_requests(
      requests,
      responses: {
        "/execution_runtime_api/control/report" => { code: "409", body: { "result" => "stale", "mailbox_items" => [] } },
      }
    ) do
      client = Shared::ControlPlane::Client.new(
        base_url: "https://core-matrix.example.test",
        execution_runtime_connection_credential: "execution-secret"
      )

      response = client.report!(payload: { "method_id" => "execution_complete" })

      assert_equal "stale", response.fetch("result")
    end

    assert_equal ["POST /execution_runtime_api/control/report"], requests.map { |entry| "#{entry.fetch(:method)} #{entry.fetch(:path)}" }
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
    when "/execution_runtime_api/control/poll"
      { "mailbox_items" => [{ "item_id" => "runtime-1", "control_plane" => "execution_runtime" }] }
    else
      { "result" => "accepted" }
    end
  end
end
