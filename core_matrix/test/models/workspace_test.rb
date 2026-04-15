require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    installation = create_installation!
    user = create_user!(installation: installation)
    workspace = Workspace.create!(
      installation: installation,
      user: user,
      name: "Personal Workspace",
      privacy: "private"
    )

    assert workspace.public_id.present?
    assert_equal workspace, Workspace.find_by_public_id!(workspace.public_id)
  end

  test "is a private user-owned root without direct agent or runtime bindings" do
    installation = create_installation!
    user = create_user!(installation: installation)
    workspace = Workspace.new(
      installation: installation,
      user: user,
      name: "Personal Workspace",
      privacy: "private"
    )

    assert workspace.valid?, workspace.errors.full_messages.to_sentence
    assert workspace.private_workspace?
    assert_equal user, workspace.user
    assert_not_includes Workspace.column_names, "agent_id"
    assert_not_includes Workspace.column_names, "default_execution_runtime_id"
    assert_nil Workspace.reflect_on_association(:agent)
    assert_nil Workspace.reflect_on_association(:default_execution_runtime)
  end

  test "stores disabled capabilities directly on the workspace as an array" do
    installation = create_installation!
    user = create_user!(installation: installation)

    workspace = Workspace.create!(
      installation: installation,
      user: user,
      name: "Scoped Workspace",
      privacy: "private",
      disabled_capabilities: ["control"]
    )

    assert_equal ["control"], workspace.disabled_capabilities

    invalid = Workspace.new(
      installation: installation,
      user: user,
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
    workspace = Workspace.create!(
      installation: installation,
      user: user,
      name: "Feature Defaults",
      privacy: "private"
    )

    assert workspace.config.is_a?(Hash)
    assert_equal "embedded_only", workspace.feature_config("title_bootstrap").fetch("strategy")
    assert_equal "runtime_first", workspace.feature_config("prompt_compaction").fetch("strategy")
  end

  test "validates workspace config shape and feature strategies" do
    installation = create_installation!
    user = create_user!(installation: installation)

    invalid_shape = Workspace.new(
      installation: installation,
      user: user,
      name: "Invalid Config Workspace",
      privacy: "private",
      config: []
    )

    assert_not invalid_shape.valid?
    assert_includes invalid_shape.errors[:config], "must be a hash"

    invalid_mode = Workspace.new(
      installation: installation,
      user: user,
      name: "Invalid Mode Workspace",
      privacy: "private",
      config: {
        "features" => {
          "title_bootstrap" => {
            "strategy" => "manual_only",
          },
        },
      }
    )

    assert_not invalid_mode.valid?
    assert_includes invalid_mode.errors[:config], "features.title_bootstrap.strategy must be one of disabled, embedded_only, runtime_first, runtime_required"
  end

  test "exposes feature config through the features container" do
    installation = create_installation!
    user = create_user!(installation: installation)
    workspace = Workspace.create!(
      installation: installation,
      user: user,
      name: "Configured Workspace",
      privacy: "private",
      config: {
        "features" => {
          "title_bootstrap" => {
            "strategy" => "disabled",
          },
          "prompt_compaction" => {
            "strategy" => "embedded_only",
          },
        },
      }
    )

    assert_equal "disabled", workspace.feature_config("title_bootstrap").fetch("strategy")
    assert_equal "embedded_only", workspace.feature_config("prompt_compaction").fetch("strategy")
  end

  test "does not expose revoked mounts through workspace-level proxy readers" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)
    runtime = create_execution_runtime!(installation: installation)
    workspace = Workspace.create!(
      installation: installation,
      user: user,
      name: "Revoked Mount Workspace",
      privacy: "private"
    )
    workspace_agent = WorkspaceAgent.create!(
      installation: installation,
      workspace: workspace,
      agent: agent,
      default_execution_runtime: runtime
    )

    assert_equal agent, workspace.agent
    assert_equal runtime, workspace.default_execution_runtime

    workspace_agent.update!(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "owner_revoked"
    )

    assert_nil workspace.reload.agent
    assert_nil workspace.default_execution_runtime
  end

  test "keeps an owned workspace visible even when its only active mount points at a hidden agent" do
    installation = create_installation!
    user = create_user!(installation: installation)
    hidden_owner = create_user!(installation: installation)
    hidden_agent = create_agent!(
      installation: installation,
      visibility: "private",
      owner_user: hidden_owner,
      provisioning_origin: "user_created",
      key: "hidden-agent",
      display_name: "Hidden Agent"
    )
    workspace = Workspace.create!(
      installation: installation,
      user: user,
      name: "Owned Workspace",
      privacy: "private"
    )
    WorkspaceAgent.create!(
      installation: installation,
      workspace: workspace,
      agent: hidden_agent,
      lifecycle_state: "active"
    )

    assert_equal [workspace], Workspace.accessible_to_user(user).order(:id).to_a
  end
end
