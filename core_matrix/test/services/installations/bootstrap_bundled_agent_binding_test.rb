require "test_helper"

module Installations
end

class Installations::BootstrapBundledAgentBindingTest < ActiveSupport::TestCase
  test "does nothing unless bundled bootstrap is explicitly enabled" do
    installation = create_installation!
    user = create_user!(installation: installation)

    result = Installations::BootstrapBundledAgentBinding.call(
      installation: installation,
      user: user,
      configuration: bundled_agent_configuration(enabled: false)
    )

    assert_nil result
    assert_equal 0, Agent.count
    assert_equal 0, UserAgentBinding.count
    assert_equal 0, Workspace.count
  end

  test "reconciles runtime rows before binding and creates the default workspace" do
    installation = create_installation!
    user = create_user!(installation: installation, role: "admin")

    result = Installations::BootstrapBundledAgentBinding.call(
      installation: installation,
      user: user,
      configuration: bundled_agent_configuration(enabled: true)
    )

    assert_equal result.agent, result.binding.agent
    assert_equal result.binding, result.workspace.user_agent_binding
    assert_equal user, result.workspace.user
    assert_equal installation, result.workspace.installation
    assert result.workspace.is_default?
    assert_equal 1, Agent.count
    assert_equal 1, ExecutionRuntime.count
    assert_equal 1, AgentSnapshot.count
    assert_equal 1, UserAgentBinding.count
    assert_equal 1, Workspace.count
  end
end
