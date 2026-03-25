require "test_helper"

class AgentRegistrationContractTest < ActionDispatch::IntegrationTest
  test "registration and capabilities endpoints keep public method ids and tool names in stable snake_case families" do
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
        tool_catalog: default_tool_catalog("shell_exec", "subagent_spawn"),
        config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
        conversation_override_schema_snapshot: { type: "object", properties: {} },
        default_config_snapshot: default_default_config_snapshot(include_selector_slots: true),
      },
      as: :json

    assert_response :created
    registration_body = JSON.parse(response.body)

    get "/agent_api/capabilities", headers: agent_api_headers(registration_body.fetch("machine_credential"))

    assert_response :success
    capability_body = JSON.parse(response.body)

    assert_equal agent_installation.public_id, registration_body["agent_installation_id"]
    assert_equal AgentDeployment.find_by_public_id!(registration_body.fetch("deployment_id")).public_id, registration_body["deployment_id"]
    assert capability_body["protocol_methods"].all? { |entry| entry.fetch("method_id").match?(/\A[a-z0-9_]+\z/) }
    assert capability_body["tool_catalog"].all? { |entry| entry.fetch("tool_name").match?(/\A[a-z0-9_]+\z/) }
    assert capability_body["tool_catalog"].all? { |entry| %w[kernel_primitive agent_observation effect_intent].include?(entry.fetch("tool_kind")) }
    refute_equal capability_body["protocol_methods"].map { |entry| entry.fetch("method_id") }.sort,
      capability_body["tool_catalog"].map { |entry| entry.fetch("tool_name") }.sort
  end
end
