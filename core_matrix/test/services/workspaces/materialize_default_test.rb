require "test_helper"

module Workspaces
end

class Workspaces::MaterializeDefaultTest < ActiveSupport::TestCase
  test "materializes the default workspace idempotently" do
    installation = create_installation!
    user = create_user!(installation: installation)
    execution_runtime = create_execution_runtime!(installation: installation)
    agent = create_agent!(installation: installation, default_execution_runtime: execution_runtime)
    binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)

    first = nil
    second = nil

    assert_difference("Workspace.count", +1) do
      first = Workspaces::MaterializeDefault.call(user_agent_binding: binding)
      second = Workspaces::MaterializeDefault.call(user_agent_binding: binding)
    end

    assert_equal first, second
    assert_equal execution_runtime, first.default_execution_runtime
    assert first.is_default?
  end

  test "builds a virtual reference until the default workspace is materialized" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation, default_execution_runtime: nil)
    binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)

    virtual_ref = Workspaces::BuildDefaultReference.call(user_agent_binding: binding)
    workspace = Workspaces::MaterializeDefault.call(user_agent_binding: binding)
    materialized_ref = Workspaces::BuildDefaultReference.call(user_agent_binding: binding)

    assert_equal "virtual", virtual_ref.state
    assert_nil virtual_ref.workspace
    assert_nil virtual_ref.workspace_id
    assert_equal "materialized", materialized_ref.state
    assert_equal workspace, materialized_ref.workspace
    assert_equal workspace.public_id, materialized_ref.workspace_id
  end
end
