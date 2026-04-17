require "test_helper"

class AgentRegistrationContractTest < ActionDispatch::IntegrationTest
  test "agent and execution runtime registration endpoints keep public method ids and tool names in stable snake_case families" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)
    agent_onboarding_session = OnboardingSessions::Issue.call(
      installation: installation,
      target_kind: "agent",
      target: agent,
      issued_by: actor,
      expires_at: 2.hours.from_now
    )
    runtime_onboarding_session = OnboardingSessions::Issue.call(
      installation: installation,
      target_kind: "execution_runtime",
      target: nil,
      issued_by: actor,
      expires_at: 2.hours.from_now
    )

    post "/execution_runtime_api/session/open",
      params: {
        onboarding_token: runtime_onboarding_session.plaintext_token,
        endpoint_metadata: {
          transport: "http",
          base_url: "https://fenix.example.test",
        },
        version_package: {
          execution_runtime_fingerprint: "fenix-host-a",
          kind: "local",
          protocol_version: "agent-runtime/2026-04-01",
          sdk_version: "nexus-0.1.0",
          capability_payload: {
            attachment_access: { request_attachment: true },
          },
          tool_catalog: [
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
          reflected_host_metadata: {
            display_name: "Nexus",
          },
        },
      },
      as: :json

    assert_response :created
    runtime_registration_body = JSON.parse(response.body)
    agent.update!(default_execution_runtime: ExecutionRuntime.find_by_public_id!(runtime_registration_body.fetch("execution_runtime_id")))

    post "/agent_api/registrations",
      params: {
        onboarding_token: agent_onboarding_session.plaintext_token,
        endpoint_metadata: {
          transport: "http",
          base_url: "https://agents.example.test",
        },
        definition_package: {
          program_manifest_fingerprint: "fenix-release-0.1.0",
          prompt_pack_ref: "fenix/default",
          prompt_pack_fingerprint: "prompt-pack-a",
          protocol_version: "2026-03-24",
          sdk_version: "fenix-0.1.0",
          protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake"),
          tool_contract: default_tool_catalog("exec_command", "subagent_spawn"),
          canonical_config_schema: profile_aware_canonical_config_schema,
          conversation_override_schema: subagent_policy_conversation_override_schema,
          workspace_agent_settings_schema: default_workspace_agent_settings_schema,
          default_workspace_agent_settings: default_workspace_agent_settings_payload,
          default_canonical_config: profile_aware_default_canonical_config,
          reflected_surface: {
            display_name: "Fenix",
          },
        },
      },
      as: :json

    assert_response :created
    registration_body = JSON.parse(response.body)

    get "/agent_api/capabilities", headers: agent_api_headers(registration_body.fetch("agent_connection_credential"))

    assert_response :success
    capability_body = JSON.parse(response.body)

    assert_equal agent.public_id, registration_body["agent_id"]
    assert_equal "execution_runtime_session_open", runtime_registration_body["method_id"]
    assert_equal "fenix-host-a", runtime_registration_body["execution_runtime_fingerprint"]
    assert_equal "fenix-host-a", registration_body["execution_runtime_fingerprint"]
    assert_equal AgentDefinitionVersion.find_by_public_id!(registration_body.fetch("agent_definition_version_id")).public_id, registration_body["agent_definition_version_id"]
    assert_equal registration_body["execution_runtime_id"], capability_body["execution_runtime_id"]
    assert_equal "main", capability_body.dig("default_canonical_config", "interactive", "profile")
    assert_equal 3, capability_body.dig("default_canonical_config", "subagents", "max_depth")
    assert_nil capability_body.dig("conversation_override_schema", "properties", "interactive")
    assert_equal ["exec_command"], capability_body.fetch("execution_runtime_plane").fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    assert_equal ["exec_command", "subagent_spawn"], capability_body.fetch("agent_plane").fetch("tool_contract").map { |entry| entry.fetch("tool_name") }
    assert capability_body["protocol_methods"].all? { |entry| entry.fetch("method_id").match?(/\A[a-z0-9_]+\z/) }
    assert capability_body["tool_contract"].all? { |entry| entry.fetch("tool_name").match?(/\A[a-z0-9_]+\z/) }
    assert capability_body["tool_contract"].all? { |entry| %w[kernel_primitive agent_observation effect_intent].include?(entry.fetch("tool_kind")) }
    assert capability_body["effective_tool_catalog"].all? { |entry| entry.fetch("tool_name").match?(/\A[a-z0-9_]+\z/) }
    refute_equal capability_body["protocol_methods"].map { |entry| entry.fetch("method_id") }.sort,
      capability_body["tool_contract"].map { |entry| entry.fetch("tool_name") }.sort
  end
end
