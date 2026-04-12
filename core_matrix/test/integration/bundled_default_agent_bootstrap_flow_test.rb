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
    assert_equal 1, AgentDefinitionVersion.count
    assert_equal 1, UserAgentBinding.count
    assert_equal 1, Workspace.count

    binding = UserAgentBinding.find_by!(user: result.user)
    workspace = Workspace.find_by!(user_agent_binding: binding, is_default: true)
    bundled_agent = Agent.find_by!(key: "fenix")
    bundled_runtime = ExecutionRuntime.first

    assert_equal bundled_agent, binding.agent
    assert bundled_agent.visibility_public?
    assert bundled_agent.provisioning_origin_system?
    assert_nil bundled_agent.owner_user_id
    assert_equal "bundled-fenix-environment", bundled_runtime.execution_runtime_fingerprint
    assert bundled_runtime.visibility_public?
    assert bundled_runtime.provisioning_origin_system?
    assert_nil bundled_runtime.owner_user_id
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
    refute_equal first.agent_definition_version.public_id, second.agent_definition_version.public_id
  end
end
