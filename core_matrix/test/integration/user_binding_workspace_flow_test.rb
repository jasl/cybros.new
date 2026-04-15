require "test_helper"

class UserBindingWorkspaceFlowTest < ActionDispatch::IntegrationTest
  test "materializes one default workspace mount per user-agent pair without duplicates" do
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

    first_workspace = Workspaces::MaterializeDefault.call(user: first_user, agent: public_agent)
    duplicate_workspace = Workspaces::MaterializeDefault.call(user: first_user, agent: public_agent)
    second_workspace = Workspaces::MaterializeDefault.call(user: second_user, agent: public_agent)

    assert_equal 2, Workspace.count
    assert_equal 2, WorkspaceAgent.where(agent: public_agent, lifecycle_state: "active").count
    assert_equal 2, Workspace.joins(:workspace_agents).where(is_default: true, workspace_agents: { agent_id: public_agent.id }).distinct.count
    assert_equal first_workspace, duplicate_workspace
    assert_equal first_user, first_workspace.user
    assert_equal second_user, second_workspace.user
    assert first_workspace.private_workspace?
    assert second_workspace.private_workspace?
  end
end
