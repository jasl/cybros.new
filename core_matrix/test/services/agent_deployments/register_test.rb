require "test_helper"

module AgentDeployments
end

class AgentDeployments::RegisterTest < ActiveSupport::TestCase
  test "consumes an enrollment token, registers a pending deployment, and audits the registration" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_installation = create_agent_installation!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_installation: agent_installation,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    result = AgentDeployments::Register.call(
      enrollment_token: enrollment.plaintext_token,
      environment_fingerprint: "fenix-host-a",
      environment_kind: "container",
      environment_connection_metadata: {
        "transport" => "http",
        "base_url" => "https://runtime.example.test",
      },
      environment_capability_payload: {
        "conversation_attachment_upload" => false,
      },
      environment_tool_catalog: [],
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
    assert_equal "pending", result.deployment.bootstrap_state
    assert_equal result.execution_environment, result.deployment.execution_environment
    assert result.deployment.matches_machine_credential?(result.machine_credential)
    assert_equal result.capability_snapshot, result.deployment.active_capability_snapshot

    audit_log = AuditLog.find_by!(action: "agent_deployment.registered")
    assert_equal result.deployment, audit_log.subject
  end

  test "normalizes symbol-key capability contracts during registration" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent_installation = create_agent_installation!(installation: installation)
    enrollment = AgentEnrollments::Issue.call(
      agent_installation: agent_installation,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    result = AgentDeployments::Register.call(
      enrollment_token: enrollment.plaintext_token,
      environment_fingerprint: "fenix-host-a",
      environment_kind: "container",
      environment_connection_metadata: {
        transport: "http",
        base_url: "https://runtime.example.test",
      },
      environment_capability_payload: {
        conversation_attachment_upload: false,
      },
      environment_tool_catalog: [],
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

    assert_equal ["agent_health", "capabilities_handshake"], result.capability_snapshot.protocol_methods.map { |entry| entry.fetch("method_id") }
    assert_equal ["exec_command"], result.capability_snapshot.tool_catalog.map { |entry| entry.fetch("tool_name") }
    assert_equal "workspace-write", result.capability_snapshot.default_config_snapshot.fetch("sandbox")
  end
end
