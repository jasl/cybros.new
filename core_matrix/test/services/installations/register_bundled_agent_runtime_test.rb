require "test_helper"

module Installations
end

class Installations::RegisterBundledAgentRuntimeTest < ActiveSupport::TestCase
  test "reconciles bundled registry rows idempotently before any binding exists" do
    installation = create_installation!
    configuration = bundled_agent_configuration(
      enabled: true,
      profile_catalog: default_profile_catalog,
      environment_capability_payload: {
        conversation_attachment_upload: false,
      },
      protocol_methods: [
        { method_id: "agent_health" },
        { method_id: "capabilities_handshake" },
      ],
      tool_catalog: [
        {
          tool_name: "shell_exec",
          tool_kind: "kernel_primitive",
          implementation_source: "kernel",
          implementation_ref: "kernel/shell_exec",
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

    assert_equal first.agent_installation, second.agent_installation
    assert_equal first.execution_environment, second.execution_environment
    assert_equal first.deployment, second.deployment
    assert_equal 1, AgentInstallation.count
    assert_equal 1, ExecutionEnvironment.count
    assert_equal 1, AgentDeployment.count
    assert_equal 1, CapabilitySnapshot.count
    assert_equal 0, UserAgentBinding.count
    assert_equal "active", first.deployment.bootstrap_state
    assert first.deployment.healthy?
    assert_equal default_profile_catalog, first.capability_snapshot.profile_catalog
    assert_equal ["shell_exec"], first.capability_snapshot.tool_catalog.map { |entry| entry.fetch("tool_name") }
    assert_equal false, first.execution_environment.capability_payload.fetch("conversation_attachment_upload")
  end

  test "supersedes the previous active deployment when the bundled fingerprint changes" do
    installation = create_installation!

    first = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: bundled_agent_configuration(
        enabled: true,
        fingerprint: "bundled-fenix-runtime-v1",
        environment_capability_payload: {
          conversation_attachment_upload: false,
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
        environment_capability_payload: {
          conversation_attachment_upload: true,
        }
      )
    )

    assert_equal first.agent_installation, second.agent_installation
    assert_equal first.execution_environment, second.execution_environment
    refute_equal first.deployment, second.deployment
    assert_equal "superseded", first.deployment.reload.bootstrap_state
    assert_equal "active", second.deployment.bootstrap_state
    assert second.deployment.healthy?
    assert_equal "fenix-0.2.0", second.deployment.sdk_version
    assert_equal({"source" => "bundled_runtime"}, second.deployment.health_metadata)
    assert_equal second.execution_environment.connection_metadata, second.deployment.endpoint_metadata
    assert_equal "http://127.0.0.1:4200", second.execution_environment.connection_metadata.fetch("base_url")
    assert_equal true, second.execution_environment.capability_payload.fetch("conversation_attachment_upload")
    assert_equal(
      AgentDeployment.digest_machine_credential("bundled-runtime:bundled-fenix-runtime-v2"),
      second.deployment.machine_credential_digest
    )
    assert_equal 2, AgentDeployment.where(agent_installation: first.agent_installation).count
    assert_equal 2, CapabilitySnapshot.where(agent_deployment: [first.deployment, second.deployment]).count
  end
end
