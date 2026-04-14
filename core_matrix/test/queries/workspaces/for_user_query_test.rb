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
    default_workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: shared_agent,
      name: "Default Workspace",
      is_default: true
    )
    project_workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: shared_agent,
      name: "Project Workspace"
    )
    create_workspace!(
      installation: installation,
      user: other_user,
      agent: shared_agent,
      name: "Other Users Workspace",
      is_default: true
    )
    result = Workspaces::ForUserQuery.call(user: user)

    assert_equal [default_workspace, project_workspace], result
  end

  test "keeps workspaces visible when their only mounted agent is revoked" do
    context = create_workspace_context!

    assert_equal [context[:workspace]], Workspaces::ForUserQuery.call(user: context[:user])

    context[:workspace_agent].update!(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "agent_visibility_revoked"
    )

    assert_equal [context[:workspace]], Workspaces::ForUserQuery.call(user: context[:user])
  end

  test "keeps workspaces visible when the default execution runtime becomes unusable" do
    context = create_workspace_context!
    replacement_owner = create_user!(
      installation: context[:installation],
      identity: create_identity!,
      display_name: "Runtime Owner"
    )

    context[:execution_runtime].update!(
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: replacement_owner
    )

    assert_equal [context[:workspace]], Workspaces::ForUserQuery.call(user: context[:user])
  end
end
