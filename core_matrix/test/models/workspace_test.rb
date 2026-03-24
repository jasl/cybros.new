require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  test "stays private and user-owned" do
    installation = create_installation!
    user = create_user!(installation: installation)
    binding = create_user_agent_binding!(installation: installation, user: user)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: binding,
      privacy: "private"
    )

    assert workspace.private_workspace?

    invalid = Workspace.new(
      installation: installation,
      user: create_user!(installation: installation, identity: create_identity!, display_name: "Other User"),
      user_agent_binding: binding,
      name: "Foreign Workspace",
      privacy: "private",
      is_default: false
    )

    assert_not invalid.valid?
    assert_includes invalid.errors[:user], "must match the binding owner"
  end

  test "allows only one default workspace per binding" do
    installation = create_installation!
    user = create_user!(installation: installation)
    binding = create_user_agent_binding!(installation: installation, user: user)

    create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: binding,
      name: "Default",
      is_default: true
    )

    duplicate = Workspace.new(
      installation: installation,
      user: user,
      user_agent_binding: binding,
      name: "Another Default",
      privacy: "private",
      is_default: true
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_agent_binding_id], "already has a default workspace"
  end
end
