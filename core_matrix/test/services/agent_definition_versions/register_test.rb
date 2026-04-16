require "test_helper"

module AgentDefinitionVersions
end

class AgentDefinitionVersions::RegisterTest < ActiveSupport::TestCase
  test "registers an active agent connection, reconciles config state, and audits the registration" do
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

    execution_runtime = create_execution_runtime!(installation: installation, kind: "container")
    execution_runtime_version = create_execution_runtime_version!(
      installation: installation,
      execution_runtime: execution_runtime,
      execution_runtime_fingerprint: "runtime-host-a"
    )
    execution_runtime.update!(
      current_execution_runtime_version: execution_runtime_version,
      published_execution_runtime_version: execution_runtime_version
    )
    agent.update!(default_execution_runtime: execution_runtime)

    result = AgentDefinitionVersions::Register.call(
      onboarding_token: onboarding_session.plaintext_token,
      endpoint_metadata: {
        "transport" => "http",
        "base_url" => "https://agents.example.test",
      },
      definition_package: definition_package_payload
    )

    onboarding_session.reload
    agent.reload

    assert onboarding_session.agent_registered_at.present?
    assert onboarding_session.last_used_at.present?
    assert_equal execution_runtime, result.execution_runtime
    assert_equal result.agent_definition_version, agent.current_agent_definition_version
    assert_equal result.agent_definition_version, agent.published_agent_definition_version
    assert_equal result.agent_definition_version, result.agent_connection.agent_definition_version
    assert result.agent_connection.active?
    assert result.agent_connection.pending?
    assert_equal result.agent_connection, AgentConnection.find_by_plaintext_connection_credential(result.agent_connection_credential)
    assert_equal result.agent_definition_version, agent.agent_config_state.base_agent_definition_version
    assert_equal "main", agent.agent_config_state.effective_payload.dig("interactive", "default_profile_key")

    audit_log = AuditLog.find_by!(action: "agent_connection.registered")
    assert_equal result.agent_connection, audit_log.subject
  end

  test "reuses an existing definition version when the normalized package is unchanged" do
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

    first = AgentDefinitionVersions::Register.call(
      onboarding_token: onboarding_session.plaintext_token,
      endpoint_metadata: { "transport" => "http", "base_url" => "https://agents.example.test" },
      definition_package: definition_package_payload
    )

    second_session = OnboardingSessions::Issue.call(
      installation: installation,
      target_kind: "agent",
      target: agent,
      issued_by: actor,
      expires_at: 2.hours.from_now
    )

    second = AgentDefinitionVersions::Register.call(
      onboarding_token: second_session.plaintext_token,
      endpoint_metadata: { "transport" => "http", "base_url" => "https://agents.example.test/v2" },
      definition_package: definition_package_payload
    )

    assert_equal first.agent_definition_version, second.agent_definition_version
    assert_equal 1, agent.reload.agent_definition_versions.count
    assert_equal second.agent_connection, agent.active_agent_connection
    assert_equal "https://agents.example.test/v2", second.agent_connection.endpoint_metadata.fetch("base_url")
  end

  private

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
        "pragmatic" => { "role_slot" => "main" },
        "researcher" => { "role_slot" => "main", "default_subagent_profile" => true },
      },
      "canonical_config_schema" => profile_aware_canonical_config_schema,
      "conversation_override_schema" => subagent_policy_conversation_override_schema,
      "workspace_agent_settings_schema" => {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "interactive" => {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              "profile_key" => { "type" => "string" },
            },
          },
        },
      },
      "default_workspace_agent_settings" => {
        "interactive" => { "profile_key" => "pragmatic" },
      },
      "default_canonical_config" => {
        "interactive" => { "default_profile_key" => "main" },
        "role_slots" => {
          "pragmatic" => { "selector" => "role:main", "fallback_role_slot" => nil },
          "summary" => { "selector" => "role:summary", "fallback_role_slot" => "main" },
        },
        "profile_runtime_overrides" => {
          "pragmatic" => { "role_slot" => "main" },
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
end
