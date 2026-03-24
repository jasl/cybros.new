require "test_helper"

module Installations
end

class Installations::RegisterBundledAgentRuntimeTest < ActiveSupport::TestCase
  test "reconciles bundled registry rows idempotently before any binding exists" do
    installation = create_installation!
    configuration = bundled_agent_configuration(enabled: true)

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
  end
end
