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
      execution_runtime_fingerprint: "foreign-runtime-#{next_test_sequence}",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )

    workspace = Workspace.new(
      installation: installation,
      user: user,
      user_agent_binding: binding,
      name: "Foreign Runtime Workspace",
      privacy: "private",
      default_execution_runtime: foreign_runtime
    )

    assert_not workspace.valid?
    assert_includes workspace.errors[:default_execution_runtime], "must belong to the same installation"
  end
end
