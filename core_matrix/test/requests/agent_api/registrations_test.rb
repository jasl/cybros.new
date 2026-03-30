require "test_helper"

class AgentApiRegistrationsTest < ActionDispatch::IntegrationTest
  test "registration exchanges an enrollment token for machine credentials and a separated capability snapshot" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_installation = create_agent_installation!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_installation: agent_installation,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    post "/agent_api/registrations",
      params: {
        enrollment_token: enrollment.plaintext_token,
        environment_fingerprint: "fenix-host-a",
        environment_kind: "local",
        environment_connection_metadata: {
          transport: "http",
          base_url: "https://runtime.example.test",
        },
        environment_capability_payload: {
          conversation_attachment_upload: false,
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
    deployment = AgentDeployment.find_by_public_id!(response_body.fetch("deployment_id"))
    execution_environment = deployment.execution_environment
    contract = RuntimeCapabilityContract.build(capability_snapshot: deployment.active_capability_snapshot)

    assert response_body["machine_credential"].present?
    assert_equal "pending", response_body["bootstrap_state"]
    assert_equal agent_installation.public_id, response_body["agent_installation_id"]
    assert_equal execution_environment.public_id, response_body["execution_environment_id"]
    assert_equal "fenix-host-a", response_body["environment_fingerprint"]
    assert_equal false, response_body.dig("environment_capability_payload", "conversation_attachment_upload")
    assert_equal contract.contract_payload, response_body.fetch("capability_snapshot")
    assert deployment.matches_machine_credential?(response_body["machine_credential"])
    refute_includes response.body, %("#{deployment.id}")
  end

  test "registration rejects blank environment fingerprints" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_installation = create_agent_installation!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_installation: agent_installation,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    post "/agent_api/registrations",
      params: {
        enrollment_token: enrollment.plaintext_token,
        environment_fingerprint: " ",
        environment_kind: "local",
        fingerprint: "fenix-release-0.1.0",
        endpoint_metadata: {},
        protocol_version: "2026-03-24",
        sdk_version: "fenix-0.1.0",
        protocol_methods: default_protocol_methods("agent_health"),
        tool_catalog: default_tool_catalog("exec_command"),
        config_schema_snapshot: default_config_schema_snapshot,
        conversation_override_schema_snapshot: { type: "object", properties: {} },
        default_config_snapshot: default_default_config_snapshot,
      },
      as: :json

    assert_response :unprocessable_entity
    assert_equal "environment fingerprint must be provided", JSON.parse(response.body).fetch("error")
  end

  test "registration defaults the environment kind and connection metadata from endpoint metadata" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_installation = create_agent_installation!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_installation: agent_installation,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    post "/agent_api/registrations",
      params: {
        enrollment_token: enrollment.plaintext_token,
        environment_fingerprint: "fenix-host-b",
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
    deployment = AgentDeployment.find_by_public_id!(response_body.fetch("deployment_id"))
    execution_environment = deployment.execution_environment

    assert_equal "local", execution_environment.kind
    assert_equal deployment.endpoint_metadata, execution_environment.connection_metadata
    assert_equal({}, response_body.fetch("environment_capability_payload"))
    refute_includes response.body, %("#{execution_environment.id}")
  end

  test "registration rejects malformed environment capability payloads with an unprocessable response" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_installation = create_agent_installation!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_installation: agent_installation,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    assert_no_difference("AgentDeployment.count") do
      post "/agent_api/registrations",
        params: {
          enrollment_token: enrollment.plaintext_token,
          environment_fingerprint: "fenix-host-c",
          environment_capability_payload: ["invalid-capability"],
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

  test "registration rejects malformed capability contract hashes with an unprocessable response" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_installation = create_agent_installation!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_installation: agent_installation,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    assert_no_difference("AgentDeployment.count") do
      post "/agent_api/registrations",
        params: {
          enrollment_token: enrollment.plaintext_token,
          environment_fingerprint: "fenix-host-d",
          environment_capability_payload: { conversation_attachment_upload: false },
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
