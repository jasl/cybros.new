require "test_helper"

class AgentApiCapabilitiesTest < ActionDispatch::IntegrationTest
  test "capabilities refresh returns protocol methods and tool catalog as separate contract sections" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot,
      environment_tool_catalog: [
        {
          "tool_name" => "shell_exec",
          "tool_kind" => "environment_runtime",
          "implementation_source" => "execution_environment",
          "implementation_ref" => "env/shell_exec",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ],
      tool_catalog: [
        {
          "tool_name" => "shell_exec",
          "tool_kind" => "agent_observation",
          "implementation_source" => "agent",
          "implementation_ref" => "agent/shell_exec",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
        {
          "tool_name" => "compact_context",
          "tool_kind" => "agent_observation",
          "implementation_source" => "agent",
          "implementation_ref" => "agent/compact_context",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ]
    )

    get "/agent_api/capabilities", headers: agent_api_headers(registration[:machine_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    contract = RuntimeCapabilityContract.build(
      execution_environment: registration[:execution_environment],
      capability_snapshot: registration[:capability_snapshot]
    )
    shell_entry = response_body.fetch("effective_tool_catalog").find { |entry| entry.fetch("tool_name") == "shell_exec" }

    assert_equal "capabilities_refresh", response_body["method_id"]
    assert_equal registration[:execution_environment].public_id, response_body["execution_environment_id"]
    assert_equal registration[:execution_environment].environment_fingerprint, response_body["environment_fingerprint"]
    assert_equal default_profile_catalog, response_body.fetch("profile_catalog")
    assert_equal default_profile_catalog, response_body.fetch("agent_plane").fetch("profile_catalog")
    assert_equal "main", response_body.dig("default_config_snapshot", "interactive", "profile")
    assert_equal 3, response_body.dig("default_config_snapshot", "subagents", "max_depth")
    assert_nil response_body.dig("conversation_override_schema_snapshot", "properties", "interactive")
    assert_equal "boolean", response_body.dig("conversation_override_schema_snapshot", "properties", "subagents", "properties", "enabled", "type")
    assert_equal ["agent_health", "capabilities_handshake"], response_body["protocol_methods"].map { |entry| entry.fetch("method_id") }
    assert_equal ["shell_exec", "compact_context"], response_body.fetch("agent_plane").fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    assert_equal ["shell_exec"], response_body.fetch("environment_plane").fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    assert_equal "environment_runtime", shell_entry.fetch("tool_kind")
    assert_equal contract.effective_tool_catalog, response_body.fetch("effective_tool_catalog")
    assert_equal contract.environment_plane, response_body.fetch("environment_plane")
  end

  test "capabilities handshake persists a new snapshot and preserves selector-bearing defaults" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )

    post "/agent_api/capabilities",
      params: {
        fingerprint: registration[:deployment].fingerprint,
        protocol_version: "2026-03-25",
        sdk_version: "fenix-0.2.0",
        environment_capability_payload: {
          conversation_attachment_upload: false,
        },
        protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "capabilities_refresh"),
        tool_catalog: default_tool_catalog("shell_exec", "subagent_spawn"),
        profile_catalog: default_profile_catalog,
        config_schema_snapshot: profile_aware_config_schema_snapshot,
        conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
        default_config_snapshot: {
          sandbox: "workspace-write",
          interactive: {},
          subagents: { enabled: false },
        },
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    contract = RuntimeCapabilityContract.build(
      execution_environment: registration[:deployment].reload.execution_environment,
      capability_snapshot: registration[:deployment].reload.active_capability_snapshot
    )
    assert_equal 2, response_body["agent_capabilities_version"]
    assert_equal false, response_body.dig("environment_capability_payload", "conversation_attachment_upload")
    assert_equal default_profile_catalog, response_body.fetch("profile_catalog")
    assert_equal default_profile_catalog, response_body.fetch("agent_plane").fetch("profile_catalog")
    assert_equal "main", response_body.dig("default_config_snapshot", "interactive", "profile")
    assert_equal true, response_body.dig("default_config_snapshot", "subagents", "allow_nested")
    assert_equal 3, response_body.dig("default_config_snapshot", "subagents", "max_depth")
    assert_nil response_body.dig("conversation_override_schema_snapshot", "properties", "interactive")
    assert_equal ["agent_health", "capabilities_handshake", "capabilities_refresh"], response_body["protocol_methods"].map { |entry| entry.fetch("method_id") }
    assert_equal 2, registration[:deployment].reload.active_capability_snapshot.version
    assert_equal false, registration[:deployment].reload.execution_environment.capability_payload["conversation_attachment_upload"]
    assert_equal contract.effective_tool_catalog, response_body.fetch("effective_tool_catalog")
    assert_equal contract.environment_plane, response_body.fetch("environment_plane")
  end

  test "capabilities handshake rejects malformed environment payloads without replacing the active snapshot" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    previous_snapshot = registration[:deployment].active_capability_snapshot

    post "/agent_api/capabilities",
      params: {
        fingerprint: registration[:deployment].fingerprint,
        protocol_version: "2026-03-25",
        sdk_version: "fenix-0.2.0",
        environment_capability_payload: ["invalid-capability"],
        protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake"),
        tool_catalog: default_tool_catalog("shell_exec"),
        profile_catalog: ["invalid-profile"],
        config_schema_snapshot: "invalid-schema",
        conversation_override_schema_snapshot: "invalid-overrides",
        default_config_snapshot: ["invalid-defaults"],
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :unprocessable_entity

    error_message = JSON.parse(response.body).fetch("error")
    assert_includes error_message, "Capability payload must be a Hash"
    assert_equal previous_snapshot.id, registration[:deployment].reload.active_capability_snapshot.id
    assert_equal 1, registration[:deployment].active_capability_snapshot.version
  end

  test "capabilities handshake rejects malformed agent contract payloads without replacing the active snapshot" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    previous_snapshot = registration[:deployment].active_capability_snapshot

    post "/agent_api/capabilities",
      params: {
        fingerprint: registration[:deployment].fingerprint,
        protocol_version: "2026-03-25",
        sdk_version: "fenix-0.2.0",
        environment_capability_payload: { conversation_attachment_upload: false },
        protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake"),
        tool_catalog: default_tool_catalog("shell_exec"),
        profile_catalog: ["invalid-profile"],
        config_schema_snapshot: "invalid-schema",
        conversation_override_schema_snapshot: "invalid-overrides",
        default_config_snapshot: ["invalid-defaults"],
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :unprocessable_entity

    error_message = JSON.parse(response.body).fetch("error")
    assert_includes error_message, "Profile catalog must be a Hash"
    assert_includes error_message, "Config schema snapshot must be a Hash"
    assert_includes error_message, "Conversation override schema snapshot must be a Hash"
    assert_includes error_message, "Default config snapshot must be a Hash"
    assert_equal previous_snapshot.id, registration[:deployment].reload.active_capability_snapshot.id
    assert_equal 1, registration[:deployment].active_capability_snapshot.version
  end
end
