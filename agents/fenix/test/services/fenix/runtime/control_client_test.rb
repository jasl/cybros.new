require "test_helper"
require "net/http"

class Fenix::Runtime::ControlClientTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body, keyword_init: true)

  test "poll merges program and executor mailbox items and routes reports by control plane" do
    requests = []
    mailbox_items = nil

    with_captured_requests(requests) do
      client = Fenix::Runtime::ControlClient.new(
        base_url: "https://core-matrix.example.test",
        machine_credential: "secret",
        execution_machine_credential: "execution-secret"
      )

      mailbox_items = client.poll(limit: 5)
      client.report!(payload: { "method_id" => "execution_started" })
      client.report!(payload: { "method_id" => "process_started" })
      client.report!(payload: { "method_id" => "resource_closed", "resource_type" => "ProcessRun" })
    end

    assert_equal %w[program-1 executor-1], mailbox_items.map { |item| item.fetch("item_id") }
    assert_equal [
      "POST /agent_api/control/poll",
      "POST /executor_api/control/poll",
      "POST /agent_api/control/report",
      "POST /executor_api/control/report",
      "POST /executor_api/control/report",
    ], requests.map { |entry| "#{entry.fetch(:method)} #{entry.fetch(:path)}" }
    assert_equal [
      %(Token token="secret"),
      %(Token token="execution-secret"),
      %(Token token="secret"),
      %(Token token="execution-secret"),
      %(Token token="execution-secret"),
    ], requests.map { |entry| entry.fetch(:authorization) }
  end

  test "register omits authorization while heartbeat uses the program credential" do
    requests = []

    with_captured_requests(requests) do
      client = Fenix::Runtime::ControlClient.new(
        base_url: "https://core-matrix.example.test",
        machine_credential: "secret"
      )

      client.register!(
        enrollment_token: "enrollment-token",
        executor_fingerprint: "bundled-fenix-environment",
        executor_connection_metadata: { "transport" => "http", "base_url" => "http://fenix.example.test:3101" },
        fingerprint: "bundled-fenix-release-0.1.0",
        endpoint_metadata: { "transport" => "http", "base_url" => "http://fenix.example.test:3101", "runtime_manifest_path" => "/runtime/manifest" },
        protocol_version: "agent-program/2026-04-01",
        sdk_version: "fenix-0.1.0"
      )
      client.heartbeat!(health_status: "healthy", auto_resume_eligible: true)
    end

    register_request = requests.fetch(0)
    heartbeat_request = requests.fetch(1)

    assert_equal "/agent_api/registrations", register_request.fetch(:path)
    assert_nil register_request.fetch(:authorization)
    assert_equal "enrollment-token", register_request.fetch(:json_body).fetch("enrollment_token")

    assert_equal "/agent_api/heartbeats", heartbeat_request.fetch(:path)
    assert_equal %(Token token="secret"), heartbeat_request.fetch(:authorization)
    assert_equal "healthy", heartbeat_request.fetch(:json_body).fetch("health_status")
  end

  test "health and capabilities endpoints use the program credential" do
    requests = []

    with_captured_requests(requests) do
      client = Fenix::Runtime::ControlClient.new(
        base_url: "https://core-matrix.example.test",
        machine_credential: "secret"
      )

      client.health
      client.capabilities_refresh
      client.capabilities_handshake!(
        fingerprint: "bundled-fenix-release-0.1.0",
        protocol_version: "agent-program/2026-04-01",
        sdk_version: "fenix-0.1.0",
        protocol_methods: [{ "method_id" => "execution_started" }],
        tool_catalog: [{ "tool_name" => "compact_context" }]
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
    assert_equal "bundled-fenix-release-0.1.0", requests.fetch(2).dig(:json_body, "fingerprint")
  end

  test "report treats stale 409 responses as idempotent replays" do
    requests = []

    with_captured_requests(
      requests,
      responses: {
        "/agent_api/control/report" => { code: "409", body: { "result" => "stale", "mailbox_items" => [] } },
      }
    ) do
      client = Fenix::Runtime::ControlClient.new(
        base_url: "https://core-matrix.example.test",
        machine_credential: "secret"
      )

      response = client.report!(payload: { "method_id" => "agent_program_completed" })

      assert_equal "stale", response.fetch("result")
    end

    assert_equal ["POST /agent_api/control/report"], requests.map { |entry| "#{entry.fetch(:method)} #{entry.fetch(:path)}" }
  end

  test "connection_context exports the settings needed by queued mailbox execution" do
    client = Fenix::Runtime::ControlClient.new(
      base_url: "https://core-matrix.example.test",
      machine_credential: "secret",
      execution_machine_credential: "execution-secret"
    )

    assert_equal(
      {
        "base_url" => "https://core-matrix.example.test",
        "machine_credential" => "secret",
        "execution_machine_credential" => "execution-secret",
        "open_timeout" => Fenix::Runtime::ControlClient::DEFAULT_OPEN_TIMEOUT,
        "read_timeout" => Fenix::Runtime::ControlClient::DEFAULT_READ_TIMEOUT,
        "write_timeout" => Fenix::Runtime::ControlClient::DEFAULT_WRITE_TIMEOUT,
      },
      client.connection_context
    )
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
      { "mailbox_items" => [{ "item_id" => "program-1", "control_plane" => "program" }] }
    when "/executor_api/control/poll"
      { "mailbox_items" => [{ "item_id" => "executor-1", "control_plane" => "executor" }] }
    when "/agent_api/health"
      { "status" => "ok" }
    when "/agent_api/capabilities"
      { "result" => "accepted" }
    else
      { "result" => "accepted" }
    end
  end
end
