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
    shared_agent = create_agent_program!(installation: installation, key: "shared-agent")
    user_binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: shared_agent
    )
    other_binding = create_user_program_binding!(
      installation: installation,
      user: other_user,
      agent_program: shared_agent
    )
    default_workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: user_binding,
      name: "Default Workspace",
      is_default: true
    )
    project_workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: user_binding,
      name: "Project Workspace"
    )
    create_workspace!(
      installation: installation,
      user: other_user,
      user_program_binding: other_binding,
      name: "Other Users Workspace",
      is_default: true
    )
    result = Workspaces::ForUserQuery.call(user: user)

    assert_equal [default_workspace, project_workspace], result
  end
end
