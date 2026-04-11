require "test_helper"

class AgentApiRegistrationsTest < ActionDispatch::IntegrationTest
  test "registration exchanges an enrollment token for an agent connection and reflects the active execution runtime" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent: agent,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    runtime_registration = register_execution_runtime!(enrollment_token: enrollment.plaintext_token)

    post "/agent_api/registrations",
      params: {
        enrollment_token: enrollment.plaintext_token,
        fingerprint: "fenix-release-0.1.0",
        endpoint_metadata: {
          transport: "http",
          base_url: "https://agents.example.test",
        },
        protocol_version: "2026-03-24",
        sdk_version: "fenix-0.1.0",
        protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake"),
        tool_catalog: default_tool_catalog("exec_command"),
        config_schema_snapshot: default_config_schema_snapshot,
        conversation_override_schema_snapshot: { type: "object", properties: {} },
        default_config_snapshot: default_default_config_snapshot,
      },
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    agent_connection = AgentConnection.find_by_public_id!(response_body.fetch("agent_connection_id"))
    agent_snapshot = AgentSnapshot.find_by_public_id!(response_body.fetch("agent_snapshot_id"))
    execution_runtime = ExecutionRuntime.find_by_public_id!(runtime_registration.fetch("execution_runtime_id"))
    contract = RuntimeCapabilityContract.build(
      execution_runtime: execution_runtime,
      agent_snapshot: agent_snapshot
    )

    assert response_body["agent_connection_credential"].present?
    assert_equal agent.public_id, response_body["agent_id"]
    assert_equal execution_runtime.public_id, response_body["execution_runtime_id"]
    assert_equal execution_runtime.execution_runtime_fingerprint, response_body["execution_runtime_fingerprint"]
    assert_equal contract.effective_tool_catalog, response_body.fetch("effective_tool_catalog")
    assert_equal contract.agent_plane, response_body.fetch("agent_plane")
    assert_equal contract.execution_runtime_plane, response_body.fetch("execution_runtime_plane")
    assert_nil response_body["execution_runtime_connection_credential"]
    assert_equal agent_connection, AgentConnection.find_by_plaintext_connection_credential(response_body["agent_connection_credential"])
    assert agent_connection.pending?
    refute_includes response.body, %("#{agent_snapshot.id}")
    refute_includes response.body, %("#{execution_runtime.id}")
  end

  test "registration allows agents without an execution runtime" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent: agent,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    post "/agent_api/registrations",
      params: {
        enrollment_token: enrollment.plaintext_token,
        fingerprint: "fenix-chat-0.1.0",
        endpoint_metadata: {
          transport: "http",
          base_url: "https://agents.example.test",
        },
        protocol_version: "2026-03-24",
        sdk_version: "fenix-0.1.0",
        protocol_methods: default_protocol_methods("agent_health"),
        tool_catalog: default_tool_catalog("compact_context"),
        config_schema_snapshot: default_config_schema_snapshot,
        conversation_override_schema_snapshot: { type: "object", properties: {} },
        default_config_snapshot: default_default_config_snapshot,
      },
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    assert_nil response_body["execution_runtime_id"]
    assert_nil response_body["execution_runtime_fingerprint"]
    assert_equal [], response_body.fetch("execution_runtime_tool_catalog")
    assert_equal({}, response_body.fetch("execution_runtime_capability_payload"))
  end

  test "registration rejects malformed agent contract hashes with an unprocessable response" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent: agent,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    assert_no_difference("AgentSnapshot.count") do
      post "/agent_api/registrations",
        params: {
          enrollment_token: enrollment.plaintext_token,
          fingerprint: "fenix-release-0.4.0",
          endpoint_metadata: {
            transport: "http",
            base_url: "https://agents.example.test",
          },
          protocol_version: "2026-03-24",
          sdk_version: "fenix-0.4.0",
          protocol_methods: default_protocol_methods("agent_health"),
          tool_catalog: default_tool_catalog("exec_command"),
          profile_catalog: ["invalid-profile"],
          config_schema_snapshot: "invalid-schema",
          conversation_override_schema_snapshot: ["invalid-overrides"],
          default_config_snapshot: "invalid-defaults",
        },
        as: :json
    end

    assert_response :unprocessable_entity

    error_message = JSON.parse(response.body).fetch("error")
    assert_includes error_message, "Profile catalog must be a Hash"
    assert_includes error_message, "Config schema snapshot must be a Hash"
    assert_includes error_message, "Conversation override schema snapshot must be a Hash"
    assert_includes error_message, "Default config snapshot must be a Hash"
  end

  private

  def register_execution_runtime!(enrollment_token:)
    post "/execution_runtime_api/registrations",
      params: {
        enrollment_token: enrollment_token,
        execution_runtime_fingerprint: "fenix-host-a",
        execution_runtime_kind: "local",
        execution_runtime_connection_metadata: {
          transport: "http",
          base_url: "https://runtime.example.test",
        },
        execution_runtime_capability_payload: {
          attachment_access: { request_attachment: true },
        },
        execution_runtime_tool_catalog: [
          {
            tool_name: "exec_command",
            tool_kind: "execution_runtime",
            implementation_source: "execution_runtime",
            implementation_ref: "env/exec_command",
            input_schema: { type: "object", properties: {} },
            result_schema: { type: "object", properties: {} },
            streaming_support: false,
            idempotency_policy: "best_effort",
          },
        ],
      },
      as: :json

    assert_response :created
    JSON.parse(response.body)
  end
end
