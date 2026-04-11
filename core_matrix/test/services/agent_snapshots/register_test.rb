require "test_helper"

module AgentSnapshots
end

class AgentSnapshots::RegisterTest < ActiveSupport::TestCase
  test "registers an active agent connection against the current default execution runtime and audits the registration" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent: agent,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    execution_runtime = create_execution_runtime!(
      installation: installation,
      execution_runtime_fingerprint: "fenix-host-a",
      kind: "container",
      connection_metadata: {
        "transport" => "http",
        "base_url" => "https://runtime.example.test",
      }
    )
    agent.update!(default_execution_runtime: execution_runtime)

    result = AgentSnapshots::Register.call(
      enrollment_token: enrollment.plaintext_token,
      fingerprint: "fenix-release-0.1.0",
      endpoint_metadata: {
        "transport" => "http",
        "base_url" => "https://agents.example.test",
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

    refute result.enrollment.reload.consumed?
    assert_equal execution_runtime, result.execution_runtime
    assert_equal result.execution_runtime, result.agent_snapshot.agent.default_execution_runtime
    assert_equal result.agent_snapshot, result.agent_connection.agent_snapshot
    assert result.agent_connection.active?
    assert result.agent_snapshot.pending?
    assert_equal result.agent_connection, AgentConnection.find_by_plaintext_connection_credential(result.agent_connection_credential)

    audit_log = AuditLog.find_by!(action: "agent_connection.registered")
    assert_equal result.agent_connection, audit_log.subject
  end

  test "normalizes symbol-key capability contracts during registration" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent: agent,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    execution_runtime = create_execution_runtime!(
      installation: installation,
      execution_runtime_fingerprint: "fenix-host-a",
      kind: "container",
      connection_metadata: {
        "transport" => "http",
        "base_url" => "https://runtime.example.test",
      }
    )
    agent.update!(default_execution_runtime: execution_runtime)

    result = AgentSnapshots::Register.call(
      enrollment_token: enrollment.plaintext_token,
      fingerprint: "fenix-release-0.1.0",
      endpoint_metadata: {
        transport: "http",
        base_url: "https://agents.example.test",
      },
      protocol_version: "2026-03-24",
      sdk_version: "fenix-0.1.0",
      protocol_methods: [
        { method_id: "agent_health" },
        { method_id: "capabilities_handshake" },
      ],
      tool_catalog: [
        {
          tool_name: "exec_command",
          tool_kind: "kernel_primitive",
          implementation_source: "kernel",
          implementation_ref: "kernel/exec_command",
          input_schema: { type: "object", properties: {} },
          result_schema: { type: "object", properties: {} },
          streaming_support: false,
          idempotency_policy: "best_effort",
        },
      ],
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: {
        type: "object",
        properties: {},
      },
      conversation_override_schema_snapshot: {
        type: "object",
        properties: {},
      },
      default_config_snapshot: {
        sandbox: "workspace-write",
      }
    )

    assert_equal ["agent_health", "capabilities_handshake"], result.agent_snapshot.protocol_methods.map { |entry| entry.fetch("method_id") }
    assert_equal ["exec_command"], result.agent_snapshot.tool_catalog.map { |entry| entry.fetch("tool_name") }
    assert_equal "workspace-write", result.agent_snapshot.default_config_snapshot.fetch("sandbox")
    assert_equal execution_runtime, result.execution_runtime
  end
end
