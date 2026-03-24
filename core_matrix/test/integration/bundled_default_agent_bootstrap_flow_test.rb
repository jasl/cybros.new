require "test_helper"

class BundledDefaultAgentBootstrapFlowTest < ActionDispatch::IntegrationTest
  test "first-admin bootstrap auto-binds the bundled agent only after registry reconciliation" do
    result = Installations::BootstrapFirstAdmin.call(
      name: "Primary Installation",
      email: "admin@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      display_name: "Primary Admin",
      bundled_agent_configuration: bundled_agent_configuration(enabled: true)
    )

    assert result.user.admin?
    assert_equal 1, AgentInstallation.count
    assert_equal 1, ExecutionEnvironment.count
    assert_equal 1, AgentDeployment.count
    assert_equal 1, UserAgentBinding.count
    assert_equal 1, Workspace.count

    binding = UserAgentBinding.find_by!(user: result.user)
    workspace = Workspace.find_by!(user_agent_binding: binding, is_default: true)

    assert_equal AgentInstallation.find_by!(key: "fenix"), binding.agent_installation
    assert_equal result.user, workspace.user
    assert_equal result.installation, workspace.installation
    assert workspace.private_workspace?
  end
end
