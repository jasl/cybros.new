require "test_helper"

class AgentRegistryFlowTest < ActionDispatch::IntegrationTest
  test "issues onboarding sessions, registers an agent definition version, and records heartbeat state" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation, visibility: "public")
    runtime_onboarding_session = OnboardingSessions::Issue.call(
      installation: installation,
      target_kind: "execution_runtime",
      target: nil,
      issued_by: actor,
      expires_at: 2.hours.from_now
    )
    agent_onboarding_session = OnboardingSessions::Issue.call(
      installation: installation,
      target_kind: "agent",
      target: agent,
      issued_by: actor,
      expires_at: 2.hours.from_now
    )

    runtime_registration = ExecutionRuntimeVersions::Register.call(
      onboarding_token: runtime_onboarding_session.plaintext_token,
      endpoint_metadata: {
        "transport" => "http",
        "base_url" => "http://127.0.0.1:4100",
      },
      version_package: {
        "execution_runtime_fingerprint" => "fenix-host-a",
        "kind" => "local",
        "protocol_version" => "2026-03-24",
        "sdk_version" => "nexus-0.1.0",
        "capability_payload" => {},
        "tool_catalog" => [
          {
            "tool_name" => "exec_command",
            "tool_kind" => "execution_runtime",
            "implementation_source" => "execution_runtime",
            "implementation_ref" => "nexus/exec_command",
            "input_schema" => { "type" => "object", "properties" => {} },
            "result_schema" => { "type" => "object", "properties" => {} },
            "streaming_support" => false,
            "idempotency_policy" => "best_effort",
          },
        ],
        "reflected_host_metadata" => {
          "display_name" => "Nexus",
        },
      }
    )
    agent.update!(default_execution_runtime: runtime_registration.execution_runtime)

    registration = AgentDefinitionVersions::Register.call(
      onboarding_token: agent_onboarding_session.plaintext_token,
      endpoint_metadata: {
        "transport" => "http",
        "base_url" => "http://127.0.0.1:4100",
      },
      definition_package: {
        "program_manifest_fingerprint" => "fenix-release-0.1.0",
        "prompt_pack_ref" => "fenix/default",
        "prompt_pack_fingerprint" => "prompt-pack-a",
        "protocol_version" => "2026-03-24",
        "sdk_version" => "fenix-0.1.0",
        "protocol_methods" => [
          { "method_id" => "agent_health" },
          { "method_id" => "capabilities_handshake" },
        ],
        "tool_contract" => [
          {
            "tool_name" => "exec_command",
            "tool_kind" => "kernel_primitive",
            "implementation_source" => "kernel",
            "implementation_ref" => "kernel/exec_command",
            "input_schema" => { "type" => "object", "properties" => {} },
            "result_schema" => { "type" => "object", "properties" => {} },
            "streaming_support" => false,
            "idempotency_policy" => "best_effort",
          },
        ],
        "profile_policy" => default_profile_policy,
        "canonical_config_schema" => {
          "type" => "object",
          "properties" => {},
        },
        "conversation_override_schema" => {
          "type" => "object",
          "properties" => {},
        },
        "default_canonical_config" => {
          "sandbox" => "workspace-write",
        },
        "reflected_surface" => {
          "display_name" => "Fenix",
        },
      }
    )

    assert_equal "pending", registration.agent_definition_version.bootstrap_state
    assert_equal runtime_registration.execution_runtime, registration.execution_runtime
    assert_equal "fenix-host-a", registration.execution_runtime.execution_runtime_fingerprint

    travel_to Time.zone.parse("2026-03-24 12:00:00 UTC") do
      AgentConnections::RecordHeartbeat.call(
        agent_definition_version: registration.agent_definition_version,
        health_status: "healthy",
        health_metadata: { "latency_ms" => 45 },
        auto_resume_eligible: true
      )
    end

    registration.agent_definition_version.reload

    assert_equal "active", registration.agent_definition_version.bootstrap_state
    assert registration.agent_definition_version.healthy?
    assert_equal({ "latency_ms" => 45 }, registration.agent_definition_version.health_metadata)
    assert_equal 2, AuditLog.where(action: "onboarding_session.issued").count
    assert_equal 1, AuditLog.where(action: "execution_runtime_connection.registered").count
    assert_equal 1, AuditLog.where(action: "agent_connection.registered").count
  end
end
