require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: agent
    )

    assert workspace.public_id.present?
    assert_equal workspace, Workspace.find_by_public_id!(workspace.public_id)
  end

  test "stays private and user-owned" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: agent,
      privacy: "private"
    )

    assert workspace.private_workspace?
    assert_equal user, workspace.user
    assert_equal agent, workspace.agent
  end

  test "allows only one default workspace per user and agent" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)

    create_workspace!(
      installation: installation,
      user: user,
      agent: agent,
      name: "Default",
      is_default: true
    )

    duplicate = Workspace.new(
      installation: installation,
      user: user,
      agent: agent,
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
      agent: create_agent!(installation: installation),
      name: "Foreign Runtime Workspace",
      privacy: "private",
      default_execution_runtime: foreign_runtime
    )

    assert_not workspace.valid?
    assert_includes workspace.errors[:default_execution_runtime], "must belong to the same installation"
  end

  test "stores disabled capabilities directly on the workspace as an array" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)

    workspace = Workspace.create!(
      installation: installation,
      user: user,
      agent: agent,
      name: "Scoped Workspace",
      privacy: "private",
      disabled_capabilities: ["control"]
    )

    assert_equal ["control"], workspace.disabled_capabilities

    invalid = Workspace.new(
      installation: installation,
      user: user,
      agent: agent,
      name: "Invalid Capability Workspace",
      privacy: "private",
      disabled_capabilities: {}
    )

    assert_not invalid.valid?
    assert_includes invalid.errors[:disabled_capabilities], "must be an array"
  end

  test "defaults workspace feature config when workspace config is omitted" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)

    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: agent
    )

    assert workspace.config.is_a?(Hash)
    assert_equal true, workspace.feature_config("title_bootstrap").fetch("enabled")
    assert_equal "runtime_first", workspace.feature_config("title_bootstrap").fetch("mode")
    assert_equal true, workspace.feature_config("prompt_compaction").fetch("enabled")
    assert_equal "runtime_first", workspace.feature_config("prompt_compaction").fetch("mode")
  end

  test "validates workspace config shape and feature modes" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)

    invalid_shape = Workspace.new(
      installation: installation,
      user: user,
      agent: agent,
      name: "Invalid Config Workspace",
      privacy: "private",
      config: []
    )

    assert_not invalid_shape.valid?
    assert_includes invalid_shape.errors[:config], "must be a hash"

    invalid_mode = Workspace.new(
      installation: installation,
      user: user,
      agent: agent,
      name: "Invalid Mode Workspace",
      privacy: "private",
      config: {
        "features" => {
          "title_bootstrap" => {
            "enabled" => true,
            "mode" => "manual_only",
          },
        },
      }
    )

    assert_not invalid_mode.valid?
    assert_includes invalid_mode.errors[:config], "features.title_bootstrap.mode must be runtime_first or embedded_only"
  end

  test "exposes feature config through the features container" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: agent,
      config: {
        "features" => {
          "title_bootstrap" => {
            "enabled" => false,
            "mode" => "embedded_only",
          },
          "prompt_compaction" => {
            "enabled" => true,
            "mode" => "embedded_only",
          },
        },
      }
    )

    assert_equal false, workspace.feature_config("title_bootstrap").fetch("enabled")
    assert_equal "embedded_only", workspace.feature_config("title_bootstrap").fetch("mode")
    assert_equal true, workspace.feature_config("prompt_compaction").fetch("enabled")
    assert_equal "embedded_only", workspace.feature_config("prompt_compaction").fetch("mode")
  end

  test "accessible_to_user returns only owned workspaces whose agent remains visible" do
    installation = create_installation!
    user = create_user!(installation: installation)
    other_user = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Other User"
    )
    visible_agent = create_agent!(installation: installation, key: "visible-agent")
    hidden_agent = create_agent!(
      installation: installation,
      key: "hidden-agent"
    )
    visible_workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: visible_agent,
      name: "Visible Workspace"
    )
    create_workspace!(
      installation: installation,
      user: user,
      agent: hidden_agent,
      name: "Hidden Workspace"
    )
    hidden_agent.update!(
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: other_user
    )

    assert_equal [visible_workspace], Workspace.accessible_to_user(user).order(:id).to_a
  end
end
