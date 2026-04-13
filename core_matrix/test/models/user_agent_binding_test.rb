require "test_helper"

class UserAgentBindingTest < ActiveSupport::TestCase
  test "enforces one binding per user and agent" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)

    create_user_agent_binding!(
      installation: installation,
      user: user,
      agent: agent
    )

    duplicate = UserAgentBinding.new(
      installation: installation,
      user: user,
      agent: agent,
      preferences: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "requires the owner to bind private agents" do
    installation = create_installation!
    owner_user = create_user!(installation: installation)
    other_user = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Other User"
    )
    agent = create_agent!(
      installation: installation,
      key: "private-agent",
      visibility: "private",
      owner_user: owner_user
    )

    invalid_binding = UserAgentBinding.new(
      installation: installation,
      user: other_user,
      agent: agent,
      preferences: {}
    )

    assert_not invalid_binding.valid?
    assert_includes invalid_binding.errors[:user], "must own the private agent"
  end

  test "resolves workspaces and default workspace through the workspace ownership boundary" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)
    binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent: agent
    )
    default_workspace = Workspace.create!(
      installation: installation,
      user: user,
      agent: agent,
      name: "Default Workspace",
      privacy: "private",
      is_default: true
    )
    Workspace.create!(
      installation: installation,
      user: user,
      agent: agent,
      name: "Project Workspace",
      privacy: "private"
    )

    assert_equal [default_workspace.id], binding.workspaces.where(is_default: true).pluck(:id)
    assert_equal default_workspace, binding.default_workspace
  end
end
