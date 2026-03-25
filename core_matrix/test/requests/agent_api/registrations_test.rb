require "test_helper"

class AgentApiRegistrationsTest < ActionDispatch::IntegrationTest
  test "registration exchanges an enrollment token for machine credentials and a separated capability snapshot" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_installation = create_agent_installation!(installation: installation)
    execution_environment = create_execution_environment!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_installation: agent_installation,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    post "/agent_api/registrations",
      params: {
        enrollment_token: enrollment.plaintext_token,
        execution_environment_id: execution_environment.public_id,
        fingerprint: "fenix-machine-001",
        endpoint_metadata: {
          transport: "http",
          base_url: "https://agents.example.test",
        },
        protocol_version: "2026-03-24",
        sdk_version: "fenix-0.1.0",
        protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake"),
        tool_catalog: default_tool_catalog("shell_exec"),
        config_schema_snapshot: default_config_schema_snapshot,
        conversation_override_schema_snapshot: { type: "object", properties: {} },
        default_config_snapshot: default_default_config_snapshot,
      },
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    deployment = AgentDeployment.find_by_public_id!(response_body.fetch("deployment_id"))

    assert response_body["machine_credential"].present?
    assert_equal "pending", response_body["bootstrap_state"]
    assert_equal agent_installation.public_id, response_body["agent_installation_id"]
    assert_equal ["agent_health", "capabilities_handshake"], response_body.dig("capability_snapshot", "protocol_methods").map { |entry| entry.fetch("method_id") }
    assert_equal ["shell_exec"], response_body.dig("capability_snapshot", "tool_catalog").map { |entry| entry.fetch("tool_name") }
    assert deployment.matches_machine_credential?(response_body["machine_credential"])
    refute_includes response.body, %("#{deployment.id}")
  end
end
