require "test_helper"

class ExecutionRuntimeApiRegistrationsTest < ActionDispatch::IntegrationTest
  test "registration exchanges a pairing token for an execution runtime connection and current runtime version" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)
    pairing_session = PairingSessions::Issue.call(
      agent: agent,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    post "/execution_runtime_api/registrations",
      params: {
        pairing_token: pairing_session.plaintext_token,
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
    execution_runtime_version = ExecutionRuntimeVersion.find_by_public_id!(response_body.fetch("execution_runtime_version_id"))
    execution_runtime_connection = ExecutionRuntimeConnection.find_by_public_id!(response_body.fetch("execution_runtime_connection_id"))
    contract = RuntimeCapabilityContract.build(execution_runtime: execution_runtime)

    assert response_body["execution_runtime_connection_credential"].present?
    assert_equal "execution_runtime_registration", response_body.fetch("method_id")
    assert_equal execution_runtime.public_id, response_body.fetch("execution_runtime_id")
    assert_equal execution_runtime.execution_runtime_fingerprint, response_body.fetch("execution_runtime_fingerprint")
    assert_equal execution_runtime_version.public_id, response_body.fetch("execution_runtime_version_id")
    assert_equal execution_runtime.kind, response_body.fetch("execution_runtime_kind")
    assert_equal contract.execution_runtime_capability_payload, response_body.fetch("execution_runtime_capability_payload")
    assert_equal contract.execution_runtime_tool_catalog, response_body.fetch("execution_runtime_tool_catalog")
    assert_equal contract.execution_runtime_plane, response_body.fetch("execution_runtime_plane")
    assert_equal execution_runtime_connection, ExecutionRuntimeConnection.find_by_plaintext_connection_credential(response_body.fetch("execution_runtime_connection_credential"))
    refute_includes response.body, %("#{execution_runtime.id}")
    refute_includes response.body, %("#{execution_runtime_version.id}")
  end

  test "registration rejects invalid version packages with an unprocessable response" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)
    pairing_session = PairingSessions::Issue.call(
      agent: agent,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    assert_no_difference("ExecutionRuntimeVersion.count") do
      post "/execution_runtime_api/registrations",
        params: {
          pairing_token: pairing_session.plaintext_token,
          endpoint_metadata: {
            transport: "http",
            base_url: "https://runtime.example.test",
          },
          version_package: version_package_payload.merge(
            "kind" => nil,
            "tool_catalog" => "invalid-tools",
            "capability_payload" => "invalid-capabilities",
            "reflected_host_metadata" => ["invalid-host"],
          ),
        },
        as: :json
    end

    assert_response :unprocessable_entity
    error_message = JSON.parse(response.body).fetch("error")
    assert_includes error_message, "Version package kind must be a non-empty String"
    assert_includes error_message, "Version package capability_payload must be a Hash"
    assert_includes error_message, "Version package tool_catalog must be an Array"
    assert_includes error_message, "Version package reflected_host_metadata must be a Hash"
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
