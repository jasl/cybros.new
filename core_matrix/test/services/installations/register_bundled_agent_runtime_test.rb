require "test_helper"

module Installations
end

class Installations::RegisterBundledAgentRuntimeTest < ActiveSupport::TestCase
  test "reconciles bundled registry rows idempotently before any binding exists" do
    installation = create_installation!
    configuration = bundled_agent_configuration(
      enabled: true,
      profile_catalog: default_profile_catalog,
      execution_runtime_capability_payload: {
        attachment_access: { request_attachment: true },
      },
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

    first = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: configuration
    )
    second = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: configuration
    )

    assert_equal first.agent, second.agent
    assert_equal first.execution_runtime, second.execution_runtime
    assert_equal first.agent_snapshot, second.agent_snapshot
    assert_equal 1, Agent.count
    assert_equal 1, ExecutionRuntime.count
    assert_equal 1, AgentSnapshot.count
    assert_equal 1, AgentConnection.count
    assert_equal 1, ExecutionRuntimeConnection.count
    assert_equal 0, UserAgentBinding.count
    assert_equal first.execution_runtime, first.agent.default_execution_runtime
    assert first.agent.visibility_public?
    assert first.agent.provisioning_origin_system?
    assert_nil first.agent.owner_user_id
    assert first.execution_runtime.visibility_public?
    assert first.execution_runtime.provisioning_origin_system?
    assert_nil first.execution_runtime.owner_user_id
    assert_equal "active", first.agent_snapshot.bootstrap_state
    assert first.agent_snapshot.healthy?
    assert_equal first.agent_connection, AgentConnection.find_by_plaintext_connection_credential(first.agent_connection_credential)
    assert_equal first.execution_runtime_connection, ExecutionRuntimeConnection.find_by_plaintext_connection_credential(first.execution_runtime_connection_credential)
    assert_equal default_profile_catalog, first.agent_snapshot.profile_catalog
    assert_equal ["exec_command"], first.agent_snapshot.tool_catalog.map { |entry| entry.fetch("tool_name") }
    assert_equal({ "source" => "bundled_runtime" }, first.agent_connection.health_metadata)
    assert_equal true, first.execution_runtime.capability_payload.dig("attachment_access", "request_attachment")
  end

  test "supersedes the previous active agent_snapshot when the bundled fingerprint changes" do
    installation = create_installation!

    first = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: bundled_agent_configuration(
        enabled: true,
        fingerprint: "bundled-fenix-runtime-v1",
        execution_runtime_capability_payload: {
          attachment_access: { request_attachment: true },
        }
      )
    )
    second = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: bundled_agent_configuration(
        enabled: true,
        fingerprint: "bundled-fenix-runtime-v2",
        sdk_version: "fenix-0.2.0",
        connection_metadata: {
          "transport" => "http",
          "base_url" => "http://127.0.0.1:4200",
        },
        execution_runtime_capability_payload: {
          attachment_access: { request_attachment: false },
        }
      )
    )

    assert_equal first.agent, second.agent
    assert_equal first.execution_runtime, second.execution_runtime
    refute_equal first.agent_snapshot, second.agent_snapshot
    assert_equal "superseded", first.agent_snapshot.reload.bootstrap_state
    assert_equal "active", second.agent_snapshot.bootstrap_state
    assert second.agent_snapshot.healthy?
    assert_equal "fenix-0.2.0", second.agent_snapshot.sdk_version
    assert_equal({ "source" => "bundled_runtime" }, second.agent_connection.health_metadata)
    assert_equal "http://127.0.0.1:4200", second.execution_runtime.connection_metadata.fetch("base_url")
    assert_equal "http://127.0.0.1:4200", second.agent_connection.endpoint_metadata.fetch("base_url")
    assert_equal "/runtime/manifest", second.agent_connection.endpoint_metadata.fetch("runtime_manifest_path")
    assert_equal false, second.execution_runtime.capability_payload.dig("attachment_access", "request_attachment")
    assert_equal 2, AgentSnapshot.where(agent: first.agent).count
    assert_equal 2, AgentConnection.where(agent: first.agent).count
    assert_equal 1, ExecutionRuntimeConnection.where(execution_runtime: first.execution_runtime, lifecycle_state: "active").count
  end

  test "reuses the active bundled connection row while rotating explicit connection credentials" do
    installation = create_installation!
    configuration = bundled_agent_configuration(enabled: true)

    first = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: configuration,
      agent_connection_credential: "bundled-agent-credential-v1",
      execution_runtime_connection_credential: "bundled-execution-credential-v1"
    )
    second = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: configuration,
      agent_connection_credential: "bundled-agent-credential-v2",
      execution_runtime_connection_credential: "bundled-execution-credential-v2"
    )

    assert_equal first.agent_connection, second.agent_connection
    assert_equal first.execution_runtime_connection, second.execution_runtime_connection
    assert_equal 1, AgentConnection.where(agent: first.agent).count
    assert_equal 1, ExecutionRuntimeConnection.where(execution_runtime: first.execution_runtime).count
    assert_nil AgentConnection.find_by_plaintext_connection_credential("bundled-agent-credential-v1")
    assert_nil ExecutionRuntimeConnection.find_by_plaintext_connection_credential("bundled-execution-credential-v1")
    assert_equal second.agent_connection, AgentConnection.find_by_plaintext_connection_credential("bundled-agent-credential-v2")
    assert_equal second.execution_runtime_connection, ExecutionRuntimeConnection.find_by_plaintext_connection_credential("bundled-execution-credential-v2")
  end
end
