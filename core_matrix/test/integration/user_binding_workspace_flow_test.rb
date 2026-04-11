require "test_helper"

class UserBindingWorkspaceFlowTest < ActionDispatch::IntegrationTest
  test "enables a public agent without duplicate bindings and keeps workspaces private" do
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

    first_enable = UserAgentBindings::Enable.call(user: first_user, agent: public_agent)
    duplicate_enable = UserAgentBindings::Enable.call(user: first_user, agent: public_agent)
    second_enable = UserAgentBindings::Enable.call(user: second_user, agent: public_agent)

    assert_equal first_enable.binding, duplicate_enable.binding
    assert_equal first_enable.workspace, duplicate_enable.workspace
    assert_equal 2, UserAgentBinding.where(agent: public_agent).count
    assert_equal 2, Workspace.where(user_agent_binding: UserAgentBinding.where(agent: public_agent), is_default: true).count
    assert_equal first_user, first_enable.workspace.user
    assert_equal second_user, second_enable.workspace.user
    assert first_enable.workspace.private_workspace?
    assert second_enable.workspace.private_workspace?
  end
end
