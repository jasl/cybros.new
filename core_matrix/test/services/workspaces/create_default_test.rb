require "test_helper"

module Workspaces
end

class Workspaces::CreateDefaultTest < ActiveSupport::TestCase
  test "creates or reuses one default workspace inside the binding ownership boundary" do
    installation = create_installation!
    user = create_user!(installation: installation)
    execution_runtime = create_execution_runtime!(installation: installation)
    agent = create_agent!(
      installation: installation,
      default_execution_runtime: execution_runtime
    )
    binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)

    first = Workspaces::CreateDefault.call(user: user, agent: agent)
    second = Workspaces::CreateDefault.call(user: user, agent: agent)

    assert_equal first, second
    assert_equal installation, first.installation
    assert_equal user, first.user
    assert first.private_workspace?
    assert_equal execution_runtime, first.default_execution_runtime
    assert_equal agent, first.agent
    assert_equal 1, Workspace.where(user: user, agent: agent, is_default: true).count
  end

  test "allows the default workspace execution runtime to remain nil when the agent has no default" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation, default_execution_runtime: nil)
    binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)

    workspace = Workspaces::CreateDefault.call(user: user, agent: agent)

    assert_nil workspace.default_execution_runtime
  end

  test "reuses the existing default workspace when a concurrent uniqueness validation wins the race" do
    installation = create_installation!
    user = create_user!(installation: installation)
    binding = create_user_agent_binding!(installation: installation, user: user)
    existing_workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: binding.agent,
      user_agent_binding: binding,
      is_default: true
    )
    invalid_workspace = Workspace.new(
      installation: installation,
      user: user,
      agent: binding.agent,
      name: "Default Workspace",
      privacy: "private",
      is_default: true
    )
    invalid_workspace.errors.add(:agent_id, "already has a default workspace for this user")
    create_default = Workspaces::CreateDefault.new(user: user, agent: binding.agent)
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

  test "requires explicit user and agent instead of a binding" do
    installation = create_installation!
    user = create_user!(installation: installation)
    binding = create_user_agent_binding!(installation: installation, user: user)

    assert_raises(ArgumentError) do
      Workspaces::CreateDefault.call(user_agent_binding: binding)
    end
  end
end
