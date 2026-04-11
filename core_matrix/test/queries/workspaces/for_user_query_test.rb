require "test_helper"

class Workspaces::ForUserQueryTest < ActiveSupport::TestCase
  test "returns only the current users private workspaces with defaults first" do
    installation = create_installation!
    user = create_user!(installation: installation, display_name: "Workspace Owner")
    other_user = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Other User"
    )
    shared_agent = create_agent!(installation: installation, key: "shared-agent")
    user_binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent: shared_agent
    )
    other_binding = create_user_agent_binding!(
      installation: installation,
      user: other_user,
      agent: shared_agent
    )
    default_workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: user_binding,
      name: "Default Workspace",
      is_default: true
    )
    project_workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: user_binding,
      name: "Project Workspace"
    )
    create_workspace!(
      installation: installation,
      user: other_user,
      user_agent_binding: other_binding,
      name: "Other Users Workspace",
      is_default: true
    )
    result = Workspaces::ForUserQuery.call(user: user)

    assert_equal [default_workspace, project_workspace], result
  end

  test "hides workspaces whose bound resources are no longer usable by the owner" do
    context = create_workspace_context!
    replacement_owner = create_user!(
      installation: context[:installation],
      identity: create_identity!,
      display_name: "Replacement Owner"
    )

    assert_equal [context[:workspace]], Workspaces::ForUserQuery.call(user: context[:user])

    context[:agent].update!(
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: replacement_owner
    )

    assert_equal [], Workspaces::ForUserQuery.call(user: context[:user])
  end
end
