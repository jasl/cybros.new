require "test_helper"

class ExecutionRuntimeApiSessionControllerTest < ActionDispatch::IntegrationTest
  test "session open returns a connection credential, capability snapshot, and transport hints" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    onboarding_session = OnboardingSessions::Issue.call(
      installation: installation,
      target_kind: "execution_runtime",
      target: nil,
      issued_by: actor,
      expires_at: 2.hours.from_now
    )

    post "/execution_runtime_api/session/open",
      params: {
        onboarding_token: onboarding_session.plaintext_token,
        endpoint_metadata: {
          transport: "http",
          base_url: "https://runtime.example.test",
        },
        version_package: version_package_payload,
      },
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    execution_runtime = ExecutionRuntime.find_by_public_id!(response_body.fetch("execution_runtime_id"))
    contract = RuntimeCapabilityContract.build(execution_runtime: execution_runtime)

    assert_equal "execution_runtime_session_open", response_body.fetch("method_id")
    assert response_body.fetch("execution_runtime_connection_credential").present?
    assert_equal contract.execution_runtime_capability_payload, response_body.fetch("execution_runtime_capability_payload")
    assert_equal contract.execution_runtime_tool_catalog, response_body.fetch("execution_runtime_tool_catalog")
    assert_equal contract.execution_runtime_plane, response_body.fetch("execution_runtime_plane")
    assert_equal "/cable", response_body.dig("transport_hints", "websocket", "path")
    assert_equal "/execution_runtime_api/mailbox/pull", response_body.dig("transport_hints", "mailbox", "pull_path")
    assert_equal "/execution_runtime_api/events/batch", response_body.dig("transport_hints", "events", "batch_path")
    refute_includes response.body, %("#{execution_runtime.id}")
  end

  test "session refresh updates the runtime version package without a separate capabilities endpoint" do
    registration = register_agent_runtime!

    post "/execution_runtime_api/session/refresh",
      params: {
        version_package: {
          "execution_runtime_fingerprint" => registration[:execution_runtime].execution_runtime_fingerprint,
          "kind" => registration[:execution_runtime].kind,
          "protocol_version" => registration[:execution_runtime].current_execution_runtime_version.protocol_version,
          "sdk_version" => registration[:execution_runtime].current_execution_runtime_version.sdk_version,
          "capability_payload" => {
            "runtime_foundation" => {
              "docker_base_project" => "images/nexus",
            },
          },
          "tool_catalog" => registration[:execution_runtime].tool_catalog,
          "reflected_host_metadata" => registration[:execution_runtime].current_execution_runtime_version.reflected_host_metadata,
        },
      },
      headers: execution_runtime_api_headers(registration[:execution_runtime_connection_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)

    assert_equal "execution_runtime_session_refresh", response_body.fetch("method_id")
    assert_equal registration[:execution_runtime].public_id, response_body.fetch("execution_runtime_id")
    assert_equal "images/nexus", response_body.dig("execution_runtime_capability_payload", "runtime_foundation", "docker_base_project")
    assert response_body.fetch("reconciliation_report").key?("runtime_version_changed")
    assert_equal "/execution_runtime_api/mailbox/pull", response_body.dig("transport_hints", "mailbox", "pull_path")
  end

  private

  def version_package_payload
    {
      "execution_runtime_fingerprint" => "runtime-host-a",
      "kind" => "local",
      "protocol_version" => "agent-runtime/2026-04-01",
      "sdk_version" => "nexus-0.1.0",
      "capability_payload" => {
        "runtime_foundation" => {
          "docker_base_project" => "images/nexus",
        },
      },
      "tool_catalog" => [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "execution_runtime",
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "runtime/exec_command",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ],
      "reflected_host_metadata" => {
        "display_name" => "Nexus",
        "host_role" => "pairing-based execution runtime",
      },
    }
  end
end
