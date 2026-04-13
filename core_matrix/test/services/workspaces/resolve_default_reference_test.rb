require "test_helper"

class Workspaces::ResolveDefaultReferenceTest < ActiveSupport::TestCase
  test "returns the virtual reference contract through explicit workspace ownership" do
    context = create_workspace_context!

    actual = Workspaces::ResolveDefaultReference.call(
      user: context[:user],
      agent: context[:agent]
    )

    assert_equal "virtual", actual.state
    assert_nil actual.workspace_id
    assert_equal context[:agent].public_id, actual.agent_id
    assert_equal context[:user].public_id, actual.user_id
    assert_equal "Default Workspace", actual.name
    assert_equal "private", actual.privacy
    assert_equal context[:execution_runtime].public_id, actual.default_execution_runtime_id
  end

  test "returns the materialized reference contract through explicit workspace ownership" do
    context = create_workspace_context!
    default_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      user_agent_binding: context[:user_agent_binding],
      default_execution_runtime: context[:execution_runtime],
      name: "Default Workspace",
      is_default: true
    )

    actual = Workspaces::ResolveDefaultReference.call(
      user: context[:user],
      agent: context[:agent]
    )

    assert_equal "materialized", actual.state
    assert_equal default_workspace.public_id, actual.workspace_id
    assert_equal context[:agent].public_id, actual.agent_id
    assert_equal context[:user].public_id, actual.user_id
    assert_equal default_workspace.name, actual.name
    assert_equal default_workspace.privacy, actual.privacy
    assert_equal context[:execution_runtime].public_id, actual.default_execution_runtime_id
  end
end
