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
    assert_equal 0, Workspace.count
    assert_equal 0, WorkspaceAgent.count
  end

  test "reconciles runtime rows and materializes a default workspace mount for the first admin" do
    installation = create_installation!
    user = create_user!(installation: installation, role: "admin")

    result = Installations::BootstrapBundledAgentBinding.call(
      installation: installation,
      user: user,
      configuration: bundled_agent_configuration(enabled: true)
    )

    assert_equal result.agent, result.workspace_agent.agent
    assert_equal result.workspace, result.default_workspace_ref.workspace
    assert_equal "materialized", result.default_workspace_ref.state
    assert_equal user.public_id, result.default_workspace_ref.user_id
    assert_equal 1, Agent.count
    assert_equal 1, ExecutionRuntime.count
    assert_equal 1, AgentDefinitionVersion.count
    assert_equal 1, Workspace.count
    assert_equal 1, WorkspaceAgent.count
  end
end
