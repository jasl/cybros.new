require "test_helper"

class SeedBaselineTest < ActiveSupport::TestCase
  test "seeds validate the catalog and reconcile the bundled runtime without inventing user data" do
    installation = create_installation!
    initial_installation_count = Installation.count
    initial_identity_count = Identity.count
    initial_user_count = User.count
    initial_binding_count = UserAgentBinding.count
    initial_workspace_count = Workspace.count
    initial_agent_installation_count = AgentInstallation.count
    initial_environment_count = ExecutionEnvironment.count
    initial_deployment_count = AgentDeployment.count
    initial_snapshot_count = CapabilitySnapshot.count

    original_configuration = Rails.configuration.x.bundled_agent
    Rails.configuration.x.bundled_agent = bundled_agent_configuration(enabled: true)

    begin
      load Rails.root.join("db/seeds.rb")
      load Rails.root.join("db/seeds.rb")
    ensure
      Rails.configuration.x.bundled_agent = original_configuration
    end

    assert_equal initial_installation_count, Installation.count
    assert_equal installation, Installation.first
    assert_equal initial_agent_installation_count + 1, AgentInstallation.count
    assert_equal initial_environment_count + 1, ExecutionEnvironment.count
    assert_equal initial_deployment_count + 1, AgentDeployment.count
    assert_equal initial_snapshot_count + 1, CapabilitySnapshot.count
    assert_equal initial_identity_count, Identity.count
    assert_equal initial_user_count, User.count
    assert_equal initial_binding_count, UserAgentBinding.count
    assert_equal initial_workspace_count, Workspace.count
  end
end
