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
    assert_equal 1, Agent.count
    assert_equal 1, ExecutionRuntime.count
    assert_equal 1, AgentSnapshot.count
    assert_equal 1, UserAgentBinding.count
    assert_equal 1, Workspace.count

    binding = UserAgentBinding.find_by!(user: result.user)
    workspace = Workspace.find_by!(user_agent_binding: binding, is_default: true)

    assert_equal Agent.find_by!(key: "fenix"), binding.agent
    assert_equal "bundled-fenix-environment", ExecutionRuntime.first.execution_runtime_fingerprint
    assert_equal result.user, workspace.user
    assert_equal result.installation, workspace.installation
    assert workspace.private_workspace?
  end

  test "bundled runtime rotation keeps the same execution environment" do
    installation = create_installation!

    first = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: bundled_agent_configuration(
        enabled: true,
        execution_runtime_fingerprint: "bundled-fenix-environment",
        fingerprint: "bundled-fenix-release-0.1.0",
        sdk_version: "fenix-0.1.0"
      )
    )
    second = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: bundled_agent_configuration(
        enabled: true,
        execution_runtime_fingerprint: "bundled-fenix-environment",
        fingerprint: "bundled-fenix-release-0.2.0",
        sdk_version: "fenix-0.2.0"
      )
    )

    assert_equal first.execution_runtime.public_id, second.execution_runtime.public_id
    refute_equal first.agent_snapshot.public_id, second.agent_snapshot.public_id
  end
end
