require "test_helper"

class UserBindingWorkspaceFlowTest < ActionDispatch::IntegrationTest
  test "enables a public agent without duplicate bindings and materializes private workspaces on demand" do
    installation = create_installation!
    first_user = create_user!(installation: installation, role: "admin", display_name: "First User")
    second_user = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Second User"
    )
    public_agent = create_agent!(
      installation: installation,
      visibility: "public",
      key: "public-agent"
    )

    first_enable = nil
    duplicate_enable = nil
    second_enable = nil

    assert_no_difference("Workspace.count") do
      first_enable = UserAgentBindings::Enable.call(user: first_user, agent: public_agent)
      duplicate_enable = UserAgentBindings::Enable.call(user: first_user, agent: public_agent)
      second_enable = UserAgentBindings::Enable.call(user: second_user, agent: public_agent)
    end

    first_workspace = Workspaces::MaterializeDefault.call(user: first_user, agent: public_agent)
    duplicate_workspace = Workspaces::MaterializeDefault.call(user: first_user, agent: public_agent)
    second_workspace = Workspaces::MaterializeDefault.call(user: second_user, agent: public_agent)

    assert_equal first_enable.binding, duplicate_enable.binding
    assert_equal "virtual", first_enable.default_workspace_ref.state
    assert_equal "virtual", duplicate_enable.default_workspace_ref.state
    assert_equal 2, UserAgentBinding.where(agent: public_agent).count
    assert_equal 2, Workspace.where(agent: public_agent, is_default: true).count
    assert_equal first_workspace, duplicate_workspace
    assert_equal first_user, first_workspace.user
    assert_equal second_user, second_workspace.user
    assert first_workspace.private_workspace?
    assert second_workspace.private_workspace?
  end
end
