require "test_helper"

module Workspaces
end

class Workspaces::MaterializeDefaultTest < ActiveSupport::TestCase
  test "materializes the default workspace mount idempotently" do
    installation = create_installation!
    user = create_user!(installation: installation)
    execution_runtime = create_execution_runtime!(installation: installation)
    agent = create_agent!(installation: installation, default_execution_runtime: execution_runtime)
    first = nil
    second = nil

    assert_difference(["Workspace.count", "WorkspaceAgent.count"], +1) do
      first = Workspaces::MaterializeDefault.call(user: user, agent: agent)
      second = Workspaces::MaterializeDefault.call(user: user, agent: agent)
    end

    assert_equal first, second
    assert_equal execution_runtime, first.default_execution_runtime
    assert first.is_default?
    assert_equal agent, first.primary_workspace_agent.agent
  end

  test "only resolves a default reference after the default workspace is materialized" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation, default_execution_runtime: nil)
    virtual_ref = Workspaces::ResolveDefaultReference.call(user: user, agent: agent)
    workspace = Workspaces::MaterializeDefault.call(user: user, agent: agent)
    materialized_ref = Workspaces::ResolveDefaultReference.call(user: user, agent: agent)

    assert_nil virtual_ref
    assert_equal "materialized", materialized_ref.state
    assert_equal workspace, materialized_ref.workspace
    assert_equal workspace.public_id, materialized_ref.workspace_id
  end

  test "requires explicit user and agent instead of a binding" do
    assert_raises(ArgumentError) do
      Workspaces::MaterializeDefault.call(user_agent_binding: Object.new)
    end
  end
end
