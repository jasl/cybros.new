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
end
