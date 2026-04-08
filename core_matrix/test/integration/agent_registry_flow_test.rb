require "test_helper"

class AgentRegistryFlowTest < ActionDispatch::IntegrationTest
  test "issues enrollment registers a deployment and records heartbeat state" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_program = create_agent_program!(installation: installation, visibility: "global")
    enrollment = AgentEnrollments::Issue.call(
      agent_program: agent_program,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    registration = AgentProgramVersions::Register.call(
      enrollment_token: enrollment.plaintext_token,
      executor_fingerprint: "fenix-host-a",
      executor_kind: "local",
      executor_connection_metadata: {
        "transport" => "http",
        "base_url" => "http://127.0.0.1:4100",
      },
      executor_capability_payload: {},
      executor_tool_catalog: [],
      fingerprint: "fenix-release-0.1.0",
      endpoint_metadata: {
        "transport" => "http",
        "base_url" => "http://127.0.0.1:4100",
      },
      protocol_version: "2026-03-24",
      sdk_version: "fenix-0.1.0",
      protocol_methods: [
        { "method_id" => "agent_health" },
        { "method_id" => "capabilities_handshake" },
      ],
      tool_catalog: [
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
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: {
        "type" => "object",
        "properties" => {},
      },
      conversation_override_schema_snapshot: {
        "type" => "object",
        "properties" => {},
      },
      default_config_snapshot: {
        "sandbox" => "workspace-write",
      }
    )

    assert_equal "pending", registration.deployment.bootstrap_state
    assert_equal "fenix-host-a", registration.executor_program.executor_fingerprint

    travel_to Time.zone.parse("2026-03-24 12:00:00 UTC") do
      AgentProgramVersions::RecordHeartbeat.call(
        deployment: registration.deployment,
        health_status: "healthy",
        health_metadata: { "latency_ms" => 45 },
        auto_resume_eligible: true
      )
    end

    registration.deployment.reload

    assert_equal "active", registration.deployment.bootstrap_state
    assert registration.deployment.healthy?
    assert_equal({ "latency_ms" => 45 }, registration.deployment.health_metadata)
    assert_equal 1, AuditLog.where(action: "agent_enrollment.issued").count
    assert_equal 1, AuditLog.where(action: "agent_session.registered").count
  end
end
