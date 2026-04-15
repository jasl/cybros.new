require "test_helper"

class Workspaces::ResolveDefaultReferenceTest < ActiveSupport::TestCase
  test "returns nil when no materialized default workspace exists for the mounted agent" do
    context = create_workspace_context!

    actual = Workspaces::ResolveDefaultReference.call(
      user: context[:user],
      agent: context[:agent]
    )

    assert_nil actual
  end

  test "returns the materialized reference contract through explicit workspace ownership" do
    context = create_workspace_context!
    default_workspace = context[:workspace]
    default_workspace.update!(is_default: true, name: "Default Workspace")

    actual = Workspaces::ResolveDefaultReference.call(
      user: context[:user],
      agent: context[:agent]
    )

    assert_equal "materialized", actual.state
    assert_equal default_workspace, actual.workspace
    assert_equal default_workspace.public_id, actual.workspace_id
    assert_equal context[:workspace_agent].public_id, actual.workspace_agent_id
    assert_equal context[:agent].public_id, actual.agent_id
    assert_equal context[:user].public_id, actual.user_id
    assert_equal default_workspace.name, actual.name
    assert_equal default_workspace.privacy, actual.privacy
    assert_equal context[:execution_runtime].public_id, actual.default_execution_runtime_id
  end
end
