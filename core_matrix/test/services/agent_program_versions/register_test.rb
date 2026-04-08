require "test_helper"

module AgentProgramVersions
end

class AgentProgramVersions::RegisterTest < ActiveSupport::TestCase
  test "consumes an enrollment token, registers a pending agent session, and audits the registration" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_program = create_agent_program!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_program: agent_program,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    result = AgentProgramVersions::Register.call(
      enrollment_token: enrollment.plaintext_token,
      executor_fingerprint: "fenix-host-a",
      executor_kind: "container",
      executor_connection_metadata: {
        "transport" => "http",
        "base_url" => "https://runtime.example.test",
      },
      executor_capability_payload: {
        "attachment_access" => { "request_attachment" => true },
      },
      executor_tool_catalog: [],
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

    assert result.enrollment.reload.consumed?
    assert_equal result.executor_program, result.deployment.agent_program.default_executor_program
    assert_equal result.deployment, result.agent_session.agent_program_version
    assert result.agent_session.pending?
    assert_equal result.agent_session, AgentSession.find_by_plaintext_session_credential(result.session_credential)

    audit_log = AuditLog.find_by!(action: "agent_session.registered")
    assert_equal result.agent_session, audit_log.subject
  end

  test "normalizes symbol-key capability contracts during registration" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_program = create_agent_program!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_program: agent_program,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    result = AgentProgramVersions::Register.call(
      enrollment_token: enrollment.plaintext_token,
      executor_fingerprint: "fenix-host-a",
      executor_kind: "container",
      executor_connection_metadata: {
        transport: "http",
        base_url: "https://runtime.example.test",
      },
      executor_capability_payload: {
        attachment_access: { request_attachment: true },
      },
      executor_tool_catalog: [],
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

    assert_equal ["agent_health", "capabilities_handshake"], result.deployment.protocol_methods.map { |entry| entry.fetch("method_id") }
    assert_equal ["exec_command"], result.deployment.tool_catalog.map { |entry| entry.fetch("tool_name") }
    assert_equal "workspace-write", result.deployment.default_config_snapshot.fetch("sandbox")
  end
end
