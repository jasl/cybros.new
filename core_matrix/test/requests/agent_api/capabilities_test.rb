require "test_helper"

class AgentApiCapabilitiesTest < ActionDispatch::IntegrationTest
  test "capabilities refresh returns separate program and execution contract sections" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot,
      executor_tool_catalog: [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "executor_program",
          "implementation_source" => "executor_program",
          "implementation_ref" => "env/exec_command",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ],
      tool_catalog: [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "agent_observation",
          "implementation_source" => "agent",
          "implementation_ref" => "agent/exec_command",
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
      executor_program: registration[:executor_program],
      agent_program_version: registration[:deployment]
    )
    shell_entry = response_body.fetch("effective_tool_catalog").find { |entry| entry.fetch("tool_name") == "exec_command" }

    assert_equal "capabilities_refresh", response_body["method_id"]
    assert_equal registration[:executor_program].public_id, response_body["executor_program_id"]
    assert_equal registration[:executor_program].executor_fingerprint, response_body["executor_fingerprint"]
    assert_equal default_profile_catalog, response_body.fetch("profile_catalog")
    assert_equal default_profile_catalog, response_body.fetch("program_plane").fetch("profile_catalog")
    assert_equal "main", response_body.dig("default_config_snapshot", "interactive", "profile")
    assert_equal 3, response_body.dig("default_config_snapshot", "subagents", "max_depth")
    assert_nil response_body.dig("conversation_override_schema_snapshot", "properties", "interactive")
    assert_equal "boolean", response_body.dig("conversation_override_schema_snapshot", "properties", "subagents", "properties", "enabled", "type")
    assert_equal ["agent_health", "capabilities_handshake"], response_body["protocol_methods"].map { |entry| entry.fetch("method_id") }
    assert_equal ["exec_command", "compact_context"], response_body.fetch("program_plane").fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    assert_equal ["exec_command"], response_body.fetch("executor_plane").fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    assert_equal "executor_program", shell_entry.fetch("tool_kind")
    assert_equal contract.effective_tool_catalog, response_body.fetch("effective_tool_catalog")
    assert_equal contract.executor_plane, response_body.fetch("executor_plane")
  end

  test "capabilities handshake refreshes executor program capabilities without changing the frozen program version" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )

    post "/agent_api/capabilities",
      params: {
        fingerprint: registration[:deployment].fingerprint,
        protocol_version: registration[:deployment].protocol_version,
        sdk_version: registration[:deployment].sdk_version,
        executor_capability_payload: {
          attachment_access: { request_attachment: true },
        },
        protocol_methods: registration[:deployment].protocol_methods,
        tool_catalog: registration[:deployment].tool_catalog,
        profile_catalog: registration[:deployment].profile_catalog,
        config_schema_snapshot: registration[:deployment].config_schema_snapshot,
        conversation_override_schema_snapshot: registration[:deployment].conversation_override_schema_snapshot,
        default_config_snapshot: registration[:deployment].default_config_snapshot,
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    contract = RuntimeCapabilityContract.build(
      executor_program: registration[:executor_program].reload,
      agent_program_version: registration[:deployment]
    )

    assert_equal registration[:deployment].fingerprint, response_body.dig("program_plane", "program_version_fingerprint")
    assert_equal true, response_body.dig("executor_capability_payload", "attachment_access", "request_attachment")
    assert_equal default_profile_catalog, response_body.fetch("profile_catalog")
    assert_equal default_profile_catalog, response_body.fetch("program_plane").fetch("profile_catalog")
    assert_equal contract.effective_tool_catalog, response_body.fetch("effective_tool_catalog")
    assert_equal contract.executor_plane, response_body.fetch("executor_plane")
    assert_equal true, registration[:executor_program].reload.capability_payload.dig("attachment_access", "request_attachment")
  end

  test "capabilities handshake rejects malformed execution payloads without changing the runtime contract" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    previous_runtime_payload = registration[:executor_program].capability_payload.deep_dup

    post "/agent_api/capabilities",
      params: {
        fingerprint: registration[:deployment].fingerprint,
        protocol_version: registration[:deployment].protocol_version,
        sdk_version: registration[:deployment].sdk_version,
        executor_capability_payload: ["invalid-capability"],
        protocol_methods: registration[:deployment].protocol_methods,
        tool_catalog: registration[:deployment].tool_catalog,
        profile_catalog: registration[:deployment].profile_catalog,
        config_schema_snapshot: registration[:deployment].config_schema_snapshot,
        conversation_override_schema_snapshot: registration[:deployment].conversation_override_schema_snapshot,
        default_config_snapshot: registration[:deployment].default_config_snapshot,
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :unprocessable_entity

    error_message = JSON.parse(response.body).fetch("error")
    assert_includes error_message, "Capability payload must be a Hash"
    assert_equal previous_runtime_payload, registration[:executor_program].reload.capability_payload
  end

  test "capabilities handshake rejects malformed program contract payloads without changing the runtime contract" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    previous_runtime_payload = registration[:executor_program].capability_payload.deep_dup

    post "/agent_api/capabilities",
      params: {
        fingerprint: registration[:deployment].fingerprint,
        protocol_version: registration[:deployment].protocol_version,
        sdk_version: registration[:deployment].sdk_version,
        executor_capability_payload: { attachment_access: { request_attachment: true } },
        protocol_methods: registration[:deployment].protocol_methods,
        tool_catalog: registration[:deployment].tool_catalog,
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
    assert_equal previous_runtime_payload, registration[:executor_program].reload.capability_payload
  end
end
