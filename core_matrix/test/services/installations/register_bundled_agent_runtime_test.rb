require "test_helper"

module Installations
end

class Installations::RegisterBundledAgentRuntimeTest < ActiveSupport::TestCase
  test "reconciles bundled registry rows idempotently before any binding exists" do
    installation = create_installation!
    configuration = bundled_agent_configuration(
      enabled: true,
      profile_catalog: default_profile_catalog,
      execution_capability_payload: {
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

    assert_equal first.agent_program, second.agent_program
    assert_equal first.execution_runtime, second.execution_runtime
    assert_equal first.deployment, second.deployment
    assert_equal 1, AgentProgram.count
    assert_equal 1, ExecutionRuntime.count
    assert_equal 1, AgentProgramVersion.count
    assert_equal 1, AgentSession.count
    assert_equal 1, ExecutionSession.count
    assert_equal 0, UserProgramBinding.count
    assert_equal "active", first.deployment.bootstrap_state
    assert first.deployment.healthy?
    assert_equal first.agent_session, AgentSession.find_by_plaintext_session_credential(first.session_credential)
    assert_equal first.execution_session, ExecutionSession.find_by_plaintext_session_credential(first.execution_session_credential)
    assert_equal default_profile_catalog, first.deployment.profile_catalog
    assert_equal ["exec_command"], first.deployment.tool_catalog.map { |entry| entry.fetch("tool_name") }
    assert_equal({ "source" => "bundled_runtime" }, first.agent_session.health_metadata)
    assert_equal true, first.execution_runtime.capability_payload.dig("attachment_access", "request_attachment")
  end

  test "supersedes the previous active deployment when the bundled fingerprint changes" do
    installation = create_installation!

    first = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: bundled_agent_configuration(
        enabled: true,
        fingerprint: "bundled-fenix-runtime-v1",
        execution_capability_payload: {
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
        execution_capability_payload: {
          attachment_access: { request_attachment: false },
        }
      )
    )

    assert_equal first.agent_program, second.agent_program
    assert_equal first.execution_runtime, second.execution_runtime
    refute_equal first.deployment, second.deployment
    assert_equal "superseded", first.deployment.reload.bootstrap_state
    assert_equal "active", second.deployment.bootstrap_state
    assert second.deployment.healthy?
    assert_equal "fenix-0.2.0", second.deployment.sdk_version
    assert_equal({ "source" => "bundled_runtime" }, second.agent_session.health_metadata)
    assert_equal "http://127.0.0.1:4200", second.execution_runtime.connection_metadata.fetch("base_url")
    assert_equal "http://127.0.0.1:4200", second.agent_session.endpoint_metadata.fetch("base_url")
    assert_equal "/runtime/manifest", second.agent_session.endpoint_metadata.fetch("runtime_manifest_path")
    assert_equal false, second.execution_runtime.capability_payload.dig("attachment_access", "request_attachment")
    assert_equal 2, AgentProgramVersion.where(agent_program: first.agent_program).count
    assert_equal 2, AgentSession.where(agent_program: first.agent_program).count
    assert_equal 1, ExecutionSession.where(execution_runtime: first.execution_runtime, lifecycle_state: "active").count
  end

  test "reuses the active bundled session row while rotating explicit session credentials" do
    installation = create_installation!
    configuration = bundled_agent_configuration(enabled: true)

    first = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: configuration,
      session_credential: "bundled-program-credential-v1",
      execution_session_credential: "bundled-execution-credential-v1"
    )
    second = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: configuration,
      session_credential: "bundled-program-credential-v2",
      execution_session_credential: "bundled-execution-credential-v2"
    )

    assert_equal first.agent_session, second.agent_session
    assert_equal first.execution_session, second.execution_session
    assert_equal 1, AgentSession.where(agent_program: first.agent_program).count
    assert_equal 1, ExecutionSession.where(execution_runtime: first.execution_runtime).count
    assert_nil AgentSession.find_by_plaintext_session_credential("bundled-program-credential-v1")
    assert_nil ExecutionSession.find_by_plaintext_session_credential("bundled-execution-credential-v1")
    assert_equal second.agent_session, AgentSession.find_by_plaintext_session_credential("bundled-program-credential-v2")
    assert_equal second.execution_session, ExecutionSession.find_by_plaintext_session_credential("bundled-execution-credential-v2")
  end
end
