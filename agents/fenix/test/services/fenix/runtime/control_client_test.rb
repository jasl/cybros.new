require "test_helper"
require "net/http"

class Fenix::Runtime::ControlClientTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body, keyword_init: true)

  test "uses ssl when the configured core matrix base url is https" do
    observed = nil
    response = Response.new(code: "200", body: JSON.generate({ "result" => "accepted" }))
    http = Object.new
    http.define_singleton_method(:request) { |_request| response }

    with_stubbed_http_start do
      ::Net::HTTP.singleton_class.define_method(:start) do |host, port, use_ssl: false, open_timeout: nil, read_timeout: nil, write_timeout: nil, &block|
        observed = { host:, port:, use_ssl:, open_timeout:, read_timeout:, write_timeout: }
        block.call(http)
      end

      client = Fenix::Runtime::ControlClient.new(
        base_url: "https://core-matrix.example.test",
        machine_credential: "secret",
        open_timeout: 3,
        read_timeout: 11,
        write_timeout: 17
      )

      client.report!(payload: { "method_id" => "execution_started" })
    end

    assert_equal "core-matrix.example.test", observed.fetch(:host)
    assert_equal 443, observed.fetch(:port)
    assert_equal true, observed.fetch(:use_ssl)
    assert_equal 3, observed.fetch(:open_timeout)
    assert_equal 11, observed.fetch(:read_timeout)
    assert_equal 17, observed.fetch(:write_timeout)
  end

  test "register posts without machine credentials while authenticated endpoints include them" do
    requests = []

    with_captured_requests(requests) do
      client = Fenix::Runtime::ControlClient.new(
        base_url: "https://core-matrix.example.test",
        machine_credential: "secret",
        execution_machine_credential: "execution-secret"
      )

      client.register!(
        enrollment_token: "enroll-123",
        runtime_fingerprint: "fenix:test",
        runtime_connection_metadata: { "transport" => "http" },
        fingerprint: "deployment-fingerprint",
        endpoint_metadata: { "base_url" => "https://fenix.example.test" },
        protocol_version: "agent-program/2026-04-01",
        sdk_version: "fenix-0.1.0"
      )
      client.heartbeat!(health_status: "healthy", auto_resume_eligible: true)
    end

    register_request = requests.fetch(0)
    heartbeat_request = requests.fetch(1)

    assert_equal "POST", register_request.fetch(:method)
    assert_equal "/program_api/registrations", register_request.fetch(:path)
    assert_nil register_request.fetch(:authorization)
    assert_equal "enroll-123", register_request.fetch(:json_body).fetch("enrollment_token")

    assert_equal "POST", heartbeat_request.fetch(:method)
    assert_equal "/program_api/heartbeats", heartbeat_request.fetch(:path)
    assert_equal %(Token token="secret"), heartbeat_request.fetch(:authorization)
    assert_equal "healthy", heartbeat_request.fetch(:json_body).fetch("health_status")
  end

  test "covers pairing, transcript, variable, human interaction, and runtime resource endpoints" do
    requests = []

    with_captured_requests(requests) do
      client = Fenix::Runtime::ControlClient.new(
        base_url: "https://core-matrix.example.test",
        machine_credential: "secret",
        execution_machine_credential: "execution-secret"
      )

      client.health
      client.capabilities_refresh
      client.capabilities_handshake!(
        fingerprint: "deployment-fingerprint",
        protocol_version: "agent-program/2026-04-01",
        sdk_version: "fenix-0.1.0",
        protocol_methods: [{ "method_id" => "agent_health" }]
      )
      client.conversation_transcript_list(conversation_id: "conversation-1", limit: 10)
      client.conversation_variables_get(workspace_id: "workspace-1", conversation_id: "conversation-1", key: "customer_name")
      client.conversation_variables_mget(workspace_id: "workspace-1", conversation_id: "conversation-1", keys: %w[a b])
      client.conversation_variables_exists(workspace_id: "workspace-1", conversation_id: "conversation-1", key: "customer_name")
      client.conversation_variables_list_keys(workspace_id: "workspace-1", conversation_id: "conversation-1", limit: 5)
      client.conversation_variables_resolve(workspace_id: "workspace-1", conversation_id: "conversation-1")
      client.conversation_variables_set(
        workspace_id: "workspace-1",
        conversation_id: "conversation-1",
        key: "customer_name",
        typed_value_payload: { "type" => "string", "value" => "Acme" }
      )
      client.conversation_variables_delete(workspace_id: "workspace-1", conversation_id: "conversation-1", key: "customer_name")
      client.conversation_variables_promote(workspace_id: "workspace-1", conversation_id: "conversation-1", key: "customer_name")
      client.workspace_variables_list(workspace_id: "workspace-1")
      client.workspace_variables_get(workspace_id: "workspace-1", key: "support_tier")
      client.workspace_variables_mget(workspace_id: "workspace-1", keys: %w[support_tier locale])
      client.workspace_variables_write(
        workspace_id: "workspace-1",
        key: "support_tier",
        typed_value_payload: { "type" => "string", "value" => "gold" },
        source_kind: "agent_runtime_smoke"
      )
      client.request_human_interaction!(
        workflow_node_id: "workflow-node-1",
        request_type: "ApprovalRequest",
        request_payload: { "approval_scope" => "publish" }
      )
      client.create_tool_invocation!(
        agent_task_run_id: "task-1",
        tool_name: "exec_command",
        request_payload: { "command_line" => "pwd" }
      )
      client.create_command_run!(tool_invocation_id: "tool-invocation-1", command_line: "pwd")
      client.activate_command_run!(command_run_id: "command-run-1")
      client.create_process_run!(
        agent_task_run_id: "task-1",
        tool_name: "process_exec",
        kind: "background_service",
        command_line: "npm run dev"
      )
      client.request_attachment!(turn_id: "turn-1", attachment_id: "attachment-1")
      client.poll(limit: 5)
      client.report!(payload: { "method_id" => "process_started", "resource_type" => "ProcessRun", "resource_id" => "process-run-1" })
      client.report!(payload: { "method_id" => "execution_started" })
    end

    assert_equal [
      "GET /program_api/health",
      "GET /program_api/capabilities",
      "POST /program_api/capabilities",
      "GET /program_api/conversation_transcripts?conversation_id=conversation-1&limit=10",
      "GET /program_api/conversation_variables/get?workspace_id=workspace-1&conversation_id=conversation-1&key=customer_name",
      "POST /program_api/conversation_variables/mget",
      "GET /program_api/conversation_variables/exists?workspace_id=workspace-1&conversation_id=conversation-1&key=customer_name",
      "GET /program_api/conversation_variables/list_keys?workspace_id=workspace-1&conversation_id=conversation-1&limit=5",
      "GET /program_api/conversation_variables/resolve?workspace_id=workspace-1&conversation_id=conversation-1",
      "POST /program_api/conversation_variables/set",
      "POST /program_api/conversation_variables/delete",
      "POST /program_api/conversation_variables/promote",
      "GET /program_api/workspace_variables?workspace_id=workspace-1",
      "GET /program_api/workspace_variables/get?workspace_id=workspace-1&key=support_tier",
      "POST /program_api/workspace_variables/mget",
      "POST /program_api/workspace_variables/write",
      "POST /program_api/human_interactions",
      "POST /program_api/tool_invocations",
      "POST /execution_api/command_runs",
      "POST /execution_api/command_runs/command-run-1/activate",
      "POST /execution_api/process_runs",
      "POST /execution_api/attachments/request",
      "POST /program_api/control/poll",
      "POST /execution_api/control/poll",
      "POST /execution_api/control/report",
      "POST /program_api/control/report",
    ], requests.map { |entry| "#{entry.fetch(:method)} #{entry.fetch(:path)}" }
    assert_equal Array.new(18, %(Token token="secret")) +
      Array.new(4, %(Token token="execution-secret")) +
      [%(Token token="secret"), %(Token token="execution-secret"), %(Token token="execution-secret"), %(Token token="secret")],
      requests.map { |entry| entry.fetch(:authorization) }
    assert_equal "ApprovalRequest", requests.fetch(16).fetch(:json_body).fetch("request_type")
    assert_equal "process_started", requests.fetch(24).fetch(:json_body).fetch("method_id")
    assert_equal "execution_started", requests.fetch(25).fetch(:json_body).fetch("method_id")
  end

  private

  def with_captured_requests(requests)
    with_stubbed_http_start do
      response_for = method(:default_response_for)

      ::Net::HTTP.singleton_class.define_method(:start) do |_host, _port, **_kwargs, &block|
        http = Object.new
        http.define_singleton_method(:request) do |request|
          requests << {
            method: request.method,
            path: request.path,
            authorization: request["Authorization"],
            json_body: request.body.present? ? JSON.parse(request.body) : nil,
          }
          Response.new(code: "200", body: JSON.generate(response_for.call(request)))
        end

        block.call(http)
      end

      yield
    end
  end

  def default_response_for(request)
    return { "mailbox_items" => [] } if ["/program_api/control/poll", "/execution_api/control/poll"].include?(request.path)

    { "result" => "accepted" }
  end

  def with_stubbed_http_start
    original_start = ::Net::HTTP.method(:start)
    yield
  ensure
    ::Net::HTTP.singleton_class.define_method(:start, original_start)
  end
end
