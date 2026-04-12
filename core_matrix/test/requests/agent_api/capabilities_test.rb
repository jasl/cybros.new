require "test_helper"

class AgentApiCapabilitiesTest < ActionDispatch::IntegrationTest
  test "capabilities refresh returns separate agent and execution runtime sections" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot,
      execution_runtime_tool_catalog: [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "execution_runtime",
          "implementation_source" => "execution_runtime",
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

    get "/agent_api/capabilities", headers: agent_api_headers(registration[:agent_connection_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    contract = RuntimeCapabilityContract.build(
      execution_runtime: registration[:execution_runtime],
      agent_definition_version: registration[:agent_definition_version]
    )
    shell_entry = response_body.fetch("effective_tool_catalog").find { |entry| entry.fetch("tool_name") == "exec_command" }

    assert_equal "capabilities_refresh", response_body["method_id"]
    assert_equal registration[:execution_runtime].public_id, response_body["execution_runtime_id"]
    assert_equal registration[:execution_runtime].execution_runtime_fingerprint, response_body["execution_runtime_fingerprint"]
    assert_equal registration[:execution_runtime].current_execution_runtime_version.public_id, response_body["execution_runtime_version_id"]
    assert_equal registration[:agent_definition_version].public_id, response_body["agent_definition_version_id"]
    assert_equal default_profile_catalog, response_body.fetch("profile_catalog")
    assert_equal default_profile_catalog, response_body.fetch("agent_plane").fetch("profile_catalog")
    assert_equal "main", response_body.dig("default_config_snapshot", "interactive", "profile")
    assert_equal 3, response_body.dig("default_config_snapshot", "subagents", "max_depth")
    assert_nil response_body.dig("conversation_override_schema_snapshot", "properties", "interactive")
    assert_equal "boolean", response_body.dig("conversation_override_schema_snapshot", "properties", "subagents", "properties", "enabled", "type")
    assert_equal ["agent_health", "capabilities_handshake"], response_body["protocol_methods"].map { |entry| entry.fetch("method_id") }
    assert_equal ["exec_command", "compact_context"], response_body.fetch("agent_plane").fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    assert_equal ["exec_command"], response_body.fetch("execution_runtime_plane").fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    assert_equal "execution_runtime", shell_entry.fetch("tool_kind")
    assert_equal contract.effective_tool_catalog, response_body.fetch("effective_tool_catalog")
    assert_equal contract.execution_runtime_plane, response_body.fetch("execution_runtime_plane")
  end

  test "capabilities handshake refreshes the frozen agent snapshot contract without mutating the current runtime contract" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    previous_runtime_payload = registration[:execution_runtime].capability_payload.deep_dup

    post "/agent_api/capabilities",
      params: {
        definition_package: {
          "program_manifest_fingerprint" => registration[:agent_definition_version].program_manifest_fingerprint,
          "prompt_pack_ref" => registration[:agent_definition_version].prompt_pack_ref,
          "prompt_pack_fingerprint" => registration[:agent_definition_version].prompt_pack_fingerprint,
          "protocol_version" => registration[:agent_definition_version].protocol_version,
          "sdk_version" => registration[:agent_definition_version].sdk_version,
          "protocol_methods" => registration[:agent_definition_version].protocol_methods,
          "tool_contract" => registration[:agent_definition_version].tool_contract,
          "profile_policy" => registration[:agent_definition_version].profile_policy,
          "canonical_config_schema" => registration[:agent_definition_version].canonical_config_schema,
          "conversation_override_schema" => registration[:agent_definition_version].conversation_override_schema,
          "default_canonical_config" => registration[:agent_definition_version].default_canonical_config,
          "reflected_surface" => registration[:agent_definition_version].reflected_surface,
        },
      },
      headers: agent_api_headers(registration[:agent_connection_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    contract = RuntimeCapabilityContract.build(
      execution_runtime: registration[:execution_runtime].reload,
      agent_definition_version: registration[:agent_definition_version]
    )

    assert_equal registration[:agent_definition_version].definition_fingerprint, response_body.dig("agent_plane", "agent_definition_fingerprint")
    assert_equal default_profile_catalog, response_body.fetch("profile_catalog")
    assert_equal default_profile_catalog, response_body.fetch("agent_plane").fetch("profile_catalog")
    assert_equal contract.effective_tool_catalog, response_body.fetch("effective_tool_catalog")
    assert_equal contract.execution_runtime_plane, response_body.fetch("execution_runtime_plane")
    assert_equal previous_runtime_payload, registration[:execution_runtime].reload.capability_payload
  end

  test "capabilities handshake rejects malformed agent contract payloads without changing the runtime contract" do
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    previous_runtime_payload = registration[:execution_runtime].capability_payload.deep_dup

    post "/agent_api/capabilities",
      params: {
        definition_package: {
          "program_manifest_fingerprint" => registration[:agent_definition_version].program_manifest_fingerprint,
          "prompt_pack_ref" => registration[:agent_definition_version].prompt_pack_ref,
          "prompt_pack_fingerprint" => registration[:agent_definition_version].prompt_pack_fingerprint,
          "protocol_version" => registration[:agent_definition_version].protocol_version,
          "sdk_version" => registration[:agent_definition_version].sdk_version,
          "protocol_methods" => registration[:agent_definition_version].protocol_methods,
          "tool_contract" => registration[:agent_definition_version].tool_contract,
          "profile_policy" => ["invalid-profile"],
          "canonical_config_schema" => "invalid-schema",
          "conversation_override_schema" => "invalid-overrides",
          "default_canonical_config" => ["invalid-defaults"],
          "reflected_surface" => {},
        },
      },
      headers: agent_api_headers(registration[:agent_connection_credential]),
      as: :json

    assert_response :unprocessable_entity

    error_message = JSON.parse(response.body).fetch("error")
    assert_includes error_message, "Definition package profile_policy must be a Hash"
    assert_includes error_message, "Definition package canonical_config_schema must be a Hash"
    assert_includes error_message, "Definition package conversation_override_schema must be a Hash"
    assert_includes error_message, "Definition package default_canonical_config must be a Hash"
    assert_equal previous_runtime_payload, registration[:execution_runtime].reload.capability_payload
  end
end
