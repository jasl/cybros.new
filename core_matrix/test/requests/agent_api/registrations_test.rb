require "test_helper"

class AgentApiRegistrationsTest < ActionDispatch::IntegrationTest
  test "registration exchanges an onboarding token for an agent connection and reflects the active execution runtime" do
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

    runtime_registration = register_execution_runtime!(onboarding_token: runtime_onboarding_session.plaintext_token)
    agent.update!(default_execution_runtime: ExecutionRuntime.find_by_public_id!(runtime_registration.fetch("execution_runtime_id")))

    post "/agent_api/registrations",
      params: {
        onboarding_token: agent_onboarding_session.plaintext_token,
        endpoint_metadata: {
          transport: "http",
          base_url: "https://agents.example.test",
          runtime_manifest_path: "/runtime/manifest",
        },
        definition_package: definition_package_payload,
      },
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    agent_connection = AgentConnection.find_by_public_id!(response_body.fetch("agent_connection_id"))
    agent_definition_version = AgentDefinitionVersion.find_by_public_id!(response_body.fetch("agent_definition_version_id"))
    execution_runtime = ExecutionRuntime.find_by_public_id!(runtime_registration.fetch("execution_runtime_id"))
    execution_runtime_version = ExecutionRuntimeVersion.find_by_public_id!(runtime_registration.fetch("execution_runtime_version_id"))
    contract = RuntimeCapabilityContract.build(
      execution_runtime: execution_runtime,
      agent_definition_version: agent_definition_version
    )

    assert response_body["agent_connection_credential"].present?
    assert_equal agent.public_id, response_body["agent_id"]
    assert_equal agent_definition_version.public_id, response_body["agent_definition_version_id"]
    assert_equal execution_runtime.public_id, response_body["execution_runtime_id"]
    assert_equal execution_runtime.execution_runtime_fingerprint, response_body["execution_runtime_fingerprint"]
    assert_equal execution_runtime_version.public_id, response_body["execution_runtime_version_id"]
    assert_equal contract.agent_definition_fingerprint, response_body["agent_definition_fingerprint"]
    assert_equal contract.effective_tool_catalog, response_body.fetch("effective_tool_catalog")
    assert_equal contract.agent_plane, response_body.fetch("agent_plane")
    assert_equal contract.execution_runtime_plane, response_body.fetch("execution_runtime_plane")
    assert_nil response_body["execution_runtime_connection_credential"]
    assert_equal agent_connection, AgentConnection.find_by_plaintext_connection_credential(response_body["agent_connection_credential"])
    assert agent_connection.pending?
    refute_includes response.body, %("#{agent_definition_version.id}")
    refute_includes response.body, %("#{execution_runtime.id}")
    refute_includes response.body, %("#{execution_runtime_version.id}")
  end

  test "registration allows agents without an execution runtime" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)
    onboarding_session = OnboardingSessions::Issue.call(
      installation: installation,
      target_kind: "agent",
      target: agent,
      issued_by: actor,
      expires_at: 2.hours.from_now
    )

    post "/agent_api/registrations",
      params: {
        onboarding_token: onboarding_session.plaintext_token,
        endpoint_metadata: {
          transport: "http",
          base_url: "https://agents.example.test",
        },
        definition_package: definition_package_payload,
      },
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    assert_nil response_body["execution_runtime_id"]
    assert_nil response_body["execution_runtime_fingerprint"]
    assert_nil response_body["execution_runtime_version_id"]
    assert_equal [], response_body.fetch("execution_runtime_tool_catalog")
    assert_equal({}, response_body.fetch("execution_runtime_capability_payload"))
  end

  test "registration rejects malformed definition packages with an unprocessable response" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)
    onboarding_session = OnboardingSessions::Issue.call(
      installation: installation,
      target_kind: "agent",
      target: agent,
      issued_by: actor,
      expires_at: 2.hours.from_now
    )

    assert_no_difference("AgentDefinitionVersion.count") do
      post "/agent_api/registrations",
        params: {
          onboarding_token: onboarding_session.plaintext_token,
          endpoint_metadata: {
            transport: "http",
            base_url: "https://agents.example.test",
          },
          definition_package: definition_package_payload.merge(
            "protocol_methods" => "invalid-methods",
            "tool_contract" => "invalid-tools",
            "profile_policy" => ["invalid-profiles"],
            "canonical_config_schema" => "invalid-schema",
            "conversation_override_schema" => ["invalid-overrides"],
            "default_canonical_config" => "invalid-defaults",
            "reflected_surface" => ["invalid-surface"],
          ),
        },
        as: :json
    end

    assert_response :unprocessable_entity

    error_message = JSON.parse(response.body).fetch("error")
    assert_includes error_message, "Definition package protocol_methods must be an Array"
    assert_includes error_message, "Definition package profile_policy must be a Hash"
    assert_includes error_message, "Definition package canonical_config_schema must be a Hash"
    assert_includes error_message, "Definition package conversation_override_schema must be a Hash"
    assert_includes error_message, "Definition package default_canonical_config must be a Hash"
    assert_includes error_message, "Definition package reflected_surface must be a Hash"
  end

  private

  def register_execution_runtime!(onboarding_token:)
    post "/execution_runtime_api/registrations",
      params: {
        onboarding_token: onboarding_token,
        endpoint_metadata: {
          transport: "http",
          base_url: "https://runtime.example.test",
        },
        version_package: version_package_payload,
      },
      as: :json

    assert_response :created
    JSON.parse(response.body)
  end

  def definition_package_payload
    {
      "program_manifest_fingerprint" => "program-manifest-a",
      "prompt_pack_ref" => "fenix/default",
      "prompt_pack_fingerprint" => "prompt-pack-a",
      "protocol_version" => "agent-runtime/2026-04-01",
      "sdk_version" => "fenix-0.1.0",
      "protocol_methods" => default_protocol_methods("agent_health", "capabilities_handshake"),
      "tool_contract" => default_tool_catalog("compact_context"),
      "profile_policy" => {
        "main" => { "role_slot" => "main" },
        "researcher" => { "role_slot" => "main", "default_subagent_profile" => true },
      },
      "canonical_config_schema" => profile_aware_canonical_config_schema,
      "conversation_override_schema" => subagent_policy_conversation_override_schema,
      "default_canonical_config" => {
        "interactive" => { "default_profile_key" => "main" },
        "role_slots" => {
          "main" => { "selector" => "role:main", "fallback_role_slot" => nil },
          "summary" => { "selector" => "role:summary", "fallback_role_slot" => "main" },
        },
        "profile_runtime_overrides" => {
          "main" => { "role_slot" => "main" },
          "researcher" => { "role_slot" => "main" },
        },
        "subagents" => { "enabled" => true, "allow_nested" => true, "max_depth" => 3 },
        "tool_policy_overlays" => [],
        "behavior" => { "sandbox" => "workspace-write" },
      },
      "reflected_surface" => {
        "display_name" => "Fenix",
        "description" => "Default cowork agent",
      },
    }
  end

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
