require "test_helper"

class AgentRegistrationContractTest < ActionDispatch::IntegrationTest
  test "agent and execution runtime registration endpoints keep public method ids and tool names in stable snake_case families" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent: agent,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    post "/execution_runtime_api/registrations",
      params: {
        enrollment_token: enrollment.plaintext_token,
        execution_runtime_fingerprint: "fenix-host-a",
        execution_runtime_kind: "local",
        execution_runtime_connection_metadata: {
          transport: "http",
          base_url: "https://fenix.example.test",
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
    runtime_registration_body = JSON.parse(response.body)

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
        profile_catalog: default_profile_catalog,
        tool_catalog: default_tool_catalog("exec_command", "subagent_spawn"),
        config_schema_snapshot: profile_aware_config_schema_snapshot,
        conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
        default_config_snapshot: profile_aware_default_config_snapshot,
      },
      as: :json

    assert_response :created
    registration_body = JSON.parse(response.body)

    get "/agent_api/capabilities", headers: agent_api_headers(registration_body.fetch("agent_connection_credential"))

    assert_response :success
    capability_body = JSON.parse(response.body)

    assert_equal agent.public_id, registration_body["agent_id"]
    assert_equal "fenix-host-a", runtime_registration_body["execution_runtime_fingerprint"]
    assert_equal "fenix-host-a", registration_body["execution_runtime_fingerprint"]
    assert_equal AgentSnapshot.find_by_public_id!(registration_body.fetch("agent_snapshot_id")).public_id, registration_body["agent_snapshot_id"]
    assert_equal registration_body["execution_runtime_id"], capability_body["execution_runtime_id"]
    assert_equal default_profile_catalog, registration_body.dig("agent_plane", "profile_catalog")
    assert_equal default_profile_catalog, capability_body.fetch("profile_catalog")
    assert_equal default_profile_catalog, capability_body.fetch("agent_plane").fetch("profile_catalog")
    assert_equal "main", capability_body.dig("default_config_snapshot", "interactive", "profile")
    assert_equal 3, capability_body.dig("default_config_snapshot", "subagents", "max_depth")
    assert_nil capability_body.dig("conversation_override_schema_snapshot", "properties", "interactive")
    assert_equal ["exec_command"], capability_body.fetch("execution_runtime_plane").fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    assert_equal ["exec_command", "subagent_spawn"], capability_body.fetch("agent_plane").fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    assert capability_body["protocol_methods"].all? { |entry| entry.fetch("method_id").match?(/\A[a-z0-9_]+\z/) }
    assert capability_body["tool_catalog"].all? { |entry| entry.fetch("tool_name").match?(/\A[a-z0-9_]+\z/) }
    assert capability_body["tool_catalog"].all? { |entry| %w[kernel_primitive agent_observation effect_intent].include?(entry.fetch("tool_kind")) }
    assert capability_body["effective_tool_catalog"].all? { |entry| entry.fetch("tool_name").match?(/\A[a-z0-9_]+\z/) }
    refute_equal capability_body["protocol_methods"].map { |entry| entry.fetch("method_id") }.sort,
      capability_body["tool_catalog"].map { |entry| entry.fetch("tool_name") }.sort
  end
end
