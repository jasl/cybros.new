require "test_helper"

class AgentApiRegistrationsTest < ActionDispatch::IntegrationTest
  test "registration exchanges an enrollment token for a session credential and program contract" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_program = create_agent_program!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_program: agent_program,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    post "/program_api/registrations",
      params: {
        enrollment_token: enrollment.plaintext_token,
        runtime_fingerprint: "fenix-host-a",
        runtime_kind: "local",
        runtime_connection_metadata: {
          transport: "http",
          base_url: "https://runtime.example.test",
        },
        execution_capability_payload: {
          attachment_access: { request_attachment: true },
        },
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
    agent_session = AgentSession.find_by_public_id!(response_body.fetch("agent_session_id"))
    deployment = AgentProgramVersion.find_by_public_id!(response_body.fetch("agent_program_version_id"))
    execution_runtime = ExecutionRuntime.find_by_public_id!(response_body.fetch("execution_runtime_id"))
    contract = RuntimeCapabilityContract.build(
      execution_runtime: execution_runtime,
      agent_program_version: deployment
    )

    assert response_body["session_credential"].present?
    assert_equal agent_program.public_id, response_body["agent_program_id"]
    assert_equal execution_runtime.public_id, response_body["execution_runtime_id"]
    assert_equal "fenix-host-a", response_body["runtime_fingerprint"]
    assert_equal true, response_body.dig("execution_capability_payload", "attachment_access", "request_attachment")
    assert response_body["execution_machine_credential"].present?
    assert_equal contract.effective_tool_catalog, response_body.fetch("effective_tool_catalog")
    assert_equal contract.program_plane, response_body.fetch("program_plane")
    assert_equal contract.execution_plane, response_body.fetch("execution_plane")
    assert_equal agent_session, AgentSession.find_by_plaintext_session_credential(response_body["session_credential"])
    assert agent_session.pending?
    refute_includes response.body, %("#{deployment.id}")
    refute_includes response.body, %("#{execution_runtime.id}")
  end

  test "registration allows agent programs without an execution runtime" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_program = create_agent_program!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_program: agent_program,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    post "/program_api/registrations",
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
    assert_nil response_body["runtime_fingerprint"]
    assert_equal [], response_body.fetch("execution_tool_catalog")
    assert_equal({}, response_body.fetch("execution_capability_payload"))
  end

  test "registration defaults runtime kind and connection metadata from endpoint metadata" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_program = create_agent_program!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_program: agent_program,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    post "/program_api/registrations",
      params: {
        enrollment_token: enrollment.plaintext_token,
        runtime_fingerprint: "fenix-host-b",
        fingerprint: "fenix-release-0.2.0",
        endpoint_metadata: {
          transport: "http",
          base_url: "https://agents.example.test",
        },
        protocol_version: "2026-03-24",
        sdk_version: "fenix-0.2.0",
        protocol_methods: default_protocol_methods("agent_health"),
        tool_catalog: default_tool_catalog("exec_command"),
        config_schema_snapshot: default_config_schema_snapshot,
        conversation_override_schema_snapshot: { type: "object", properties: {} },
        default_config_snapshot: default_default_config_snapshot,
      },
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    execution_runtime = ExecutionRuntime.find_by_public_id!(response_body.fetch("execution_runtime_id"))

    assert_equal "local", execution_runtime.kind
    assert_equal({ "transport" => "http", "base_url" => "https://agents.example.test" }, execution_runtime.connection_metadata)
    assert_equal({}, response_body.fetch("execution_capability_payload"))
  end

  test "registration rejects malformed execution capability payloads with an unprocessable response" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_program = create_agent_program!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_program: agent_program,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    assert_no_difference("AgentProgramVersion.count") do
      post "/program_api/registrations",
        params: {
          enrollment_token: enrollment.plaintext_token,
          runtime_fingerprint: "fenix-host-c",
          execution_capability_payload: ["invalid-capability"],
          fingerprint: "fenix-release-0.3.0",
          endpoint_metadata: {
            transport: "http",
            base_url: "https://agents.example.test",
          },
          protocol_version: "2026-03-24",
          sdk_version: "fenix-0.3.0",
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
    assert_includes error_message, "Capability payload must be a Hash"
  end

  test "registration rejects malformed program contract hashes with an unprocessable response" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_program = create_agent_program!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_program: agent_program,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    assert_no_difference("AgentProgramVersion.count") do
      post "/program_api/registrations",
        params: {
          enrollment_token: enrollment.plaintext_token,
          runtime_fingerprint: "fenix-host-d",
          execution_capability_payload: { attachment_access: { request_attachment: true } },
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
end
