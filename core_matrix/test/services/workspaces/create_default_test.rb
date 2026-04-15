require "test_helper"

module Workspaces
end

class Workspaces::CreateDefaultTest < ActiveSupport::TestCase
  test "creates or reuses one default workspace with an active mounted agent" do
    installation = create_installation!
    user = create_user!(installation: installation)
    execution_runtime = create_execution_runtime!(installation: installation)
    agent = create_agent!(
      installation: installation,
      default_execution_runtime: execution_runtime
    )
    first = nil
    second = nil

    assert_difference(["Workspace.count", "WorkspaceAgent.count"], +1) do
      first = Workspaces::CreateDefault.call(user: user, agent: agent)
      second = Workspaces::CreateDefault.call(user: user, agent: agent)
    end

    assert_equal first, second
    assert_equal installation, first.installation
    assert_equal user, first.user
    assert first.private_workspace?
    assert first.is_default?
    assert_equal execution_runtime, first.default_execution_runtime
    assert_equal agent, first.agent
    assert_equal agent, first.primary_workspace_agent.agent
    assert_equal default_interactive_entry_policy_payload, first.primary_workspace_agent.entry_policy_payload
    assert_equal 1, Workspace
      .joins(:workspace_agents)
      .where(user: user, is_default: true, workspace_agents: { agent_id: agent.id, lifecycle_state: "active" })
      .distinct
      .count
  end

  test "allows the default workspace execution runtime to remain nil when the agent has no default" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation, default_execution_runtime: nil)
    workspace = Workspaces::CreateDefault.call(user: user, agent: agent)

    assert_nil workspace.default_execution_runtime
  end

  test "reuses the existing default workspace when a concurrent uniqueness validation wins the race" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)
    existing_workspace = create_workspace!(
      installation: installation,
      user: user,
      is_default: true
    )
    create_workspace_agent!(
      installation: installation,
      workspace: existing_workspace,
      agent: agent
    )
    invalid_workspace = Workspace.new(
      installation: installation,
      user: user,
      name: "Default Workspace",
      privacy: "private",
      is_default: true
    )
    invalid_workspace.errors.add(:user_id, "already has a default workspace for this user")
    create_default = Workspaces::CreateDefault.new(user: user, agent: agent)
    lookup_calls = 0

    create_default.define_singleton_method(:existing_workspace) do
      lookup_calls += 1
      lookup_calls == 1 ? nil : existing_workspace
    end

    workspace_singleton = Workspace.singleton_class
    original_create = Workspace.method(:create!)

    workspace_singleton.send(:define_method, :create!) do |*|
      raise ActiveRecord::RecordInvalid.new(invalid_workspace)
    end

    begin
      assert_equal existing_workspace, create_default.call
    ensure
      workspace_singleton.send(:define_method, :create!, original_create)
    end
  end

  test "reuses the existing default workspace when the database unique constraint wins the race" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)
    existing_workspace = create_workspace!(
      installation: installation,
      user: user,
      is_default: true
    )
    create_workspace_agent!(
      installation: installation,
      workspace: existing_workspace,
      agent: agent
    )
    create_default = Workspaces::CreateDefault.new(user: user, agent: agent)
    lookup_calls = 0

    create_default.define_singleton_method(:existing_workspace) do
      lookup_calls += 1
      lookup_calls == 1 ? nil : existing_workspace
    end

    workspace_singleton = Workspace.singleton_class
    original_create = Workspace.method(:create!)

    workspace_singleton.send(:define_method, :create!) do |*|
      raise ActiveRecord::RecordNotUnique, "duplicate default workspace"
    end

    begin
      assert_equal existing_workspace, create_default.call
    ensure
      workspace_singleton.send(:define_method, :create!, original_create)
    end
  end

  test "reuses the existing active mount when a concurrent mount validation wins the race" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)
    existing_workspace = create_workspace!(
      installation: installation,
      user: user,
      is_default: true
    )
    existing_mount = create_workspace_agent!(
      installation: installation,
      workspace: existing_workspace,
      agent: agent
    )
    invalid_mount = WorkspaceAgent.new(
      installation: installation,
      workspace: existing_workspace,
      agent: agent,
      default_execution_runtime: agent.default_execution_runtime,
      entry_policy_payload: Conversation.default_interactive_entry_policy_payload
    )
    invalid_mount.errors.add(:agent_id, "already has an active mount for this workspace")
    create_default = Workspaces::CreateDefault.new(user: user, agent: agent)

    workspace_agent_singleton = WorkspaceAgent.singleton_class
    original_create = WorkspaceAgent.method(:create!)

    workspace_agent_singleton.send(:define_method, :create!) do |*|
      raise ActiveRecord::RecordInvalid.new(invalid_mount)
    end

    begin
      assert_equal existing_workspace, create_default.call
      assert_equal existing_mount, existing_workspace.reload.primary_workspace_agent
    ensure
      workspace_agent_singleton.send(:define_method, :create!, original_create)
    end
  end

  test "rolls back default workspace creation when mount materialization fails" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)
    invalid_mount = WorkspaceAgent.new(
      installation: installation,
      workspace: Workspace.new(
        installation: installation,
        user: user,
        name: "Default Workspace",
        privacy: "private",
        is_default: true
      ),
      agent: agent,
      default_execution_runtime: agent.default_execution_runtime,
      entry_policy_payload: Conversation.default_interactive_entry_policy_payload
    )
    invalid_mount.errors.add(:base, "mount failed")

    workspace_agent_singleton = WorkspaceAgent.singleton_class
    original_create = WorkspaceAgent.method(:create!)

    workspace_agent_singleton.send(:define_method, :create!) do |*|
      raise ActiveRecord::RecordInvalid.new(invalid_mount)
    end

    begin
      assert_no_difference(["Workspace.count", "WorkspaceAgent.count"]) do
        assert_raises(ActiveRecord::RecordInvalid) do
          Workspaces::CreateDefault.call(user: user, agent: agent)
        end
      end
    ensure
      workspace_agent_singleton.send(:define_method, :create!, original_create)
    end
  end

  test "requires explicit user and agent instead of a binding" do
    assert_raises(ArgumentError) do
      Workspaces::CreateDefault.call(user_agent_binding: Object.new)
    end
  end
end
