require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    installation = create_installation!
    user = create_user!(installation: installation)
    binding = create_user_agent_binding!(installation: installation, user: user)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: binding
    )

    assert workspace.public_id.present?
    assert_equal workspace, Workspace.find_by_public_id!(workspace.public_id)
  end

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
    assert_equal user, workspace.user
    assert_equal binding.agent, workspace.agent
  end

  test "allows only one default workspace per user and agent" do
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
      agent: binding.agent,
      name: "Another Default",
      privacy: "private",
      is_default: true
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:agent_id], "already has a default workspace for this user"
  end

  test "default execution runtime must belong to the same installation" do
    installation = create_installation!
    user = create_user!(installation: installation)
    binding = create_user_agent_binding!(installation: installation, user: user)
    foreign_installation = Installation.new(
      id: installation.id.to_i + 1,
      name: "Foreign Installation",
      bootstrap_state: "bootstrapped",
      global_settings: {}
    )
    foreign_runtime = ExecutionRuntime.new(
      installation: foreign_installation,
      visibility: "public",
      provisioning_origin: "system",
      kind: "local",
      display_name: "Foreign Runtime",
      lifecycle_state: "active"
    )

    workspace = Workspace.new(
      installation: installation,
      user: user,
      agent: binding.agent,
      name: "Foreign Runtime Workspace",
      privacy: "private",
      default_execution_runtime: foreign_runtime
    )

    assert_not workspace.valid?
    assert_includes workspace.errors[:default_execution_runtime], "must belong to the same installation"
  end
end
