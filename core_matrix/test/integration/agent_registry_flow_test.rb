require "test_helper"

class AgentRegistryFlowTest < ActionDispatch::IntegrationTest
  test "issues enrollment registers a agent_snapshot and records heartbeat state" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation, visibility: "public")
    enrollment = AgentEnrollments::Issue.call(
      agent: agent,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    runtime_registration = ExecutionRuntimes::Register.call(
      enrollment_token: enrollment.plaintext_token,
      execution_runtime_fingerprint: "fenix-host-a",
      execution_runtime_kind: "local",
      execution_runtime_connection_metadata: {
        "transport" => "http",
        "base_url" => "http://127.0.0.1:4100",
      },
      execution_runtime_capability_payload: {},
      execution_runtime_tool_catalog: [
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
      ]
    )

    registration = AgentSnapshots::Register.call(
      enrollment_token: enrollment.plaintext_token,
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

    assert_equal "pending", registration.agent_snapshot.bootstrap_state
    assert_equal runtime_registration.execution_runtime, registration.execution_runtime
    assert_equal "fenix-host-a", registration.execution_runtime.execution_runtime_fingerprint

    travel_to Time.zone.parse("2026-03-24 12:00:00 UTC") do
      AgentSnapshots::RecordHeartbeat.call(
        agent_snapshot: registration.agent_snapshot,
        health_status: "healthy",
        health_metadata: { "latency_ms" => 45 },
        auto_resume_eligible: true
      )
    end

    registration.agent_snapshot.reload

    assert_equal "active", registration.agent_snapshot.bootstrap_state
    assert registration.agent_snapshot.healthy?
    assert_equal({ "latency_ms" => 45 }, registration.agent_snapshot.health_metadata)
    assert_equal 1, AuditLog.where(action: "agent_enrollment.issued").count
    assert_equal 1, AuditLog.where(action: "execution_runtime_connection.registered").count
    assert_equal 1, AuditLog.where(action: "agent_connection.registered").count
  end
end
