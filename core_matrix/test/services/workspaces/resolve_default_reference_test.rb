require "test_helper"

class Workspaces::ResolveDefaultReferenceTest < ActiveSupport::TestCase
  test "returns the same virtual reference contract as the current binding-backed resolver" do
    context = create_workspace_context!

    expected = Workspaces::BuildDefaultReference.call(
      user_agent_binding: context[:user_agent_binding]
    )
    actual = Workspaces::ResolveDefaultReference.call(
      user: context[:user],
      agent: context[:agent]
    )

    assert_equal "virtual", actual.state
    assert_equal expected.state, actual.state
    assert_nil expected.workspace_id
    assert_nil actual.workspace_id
    assert_equal expected.agent_id, actual.agent_id
    assert_equal expected.user_id, actual.user_id
    assert_equal expected.name, actual.name
    assert_equal expected.privacy, actual.privacy
    assert_equal expected.default_execution_runtime_id, actual.default_execution_runtime_id
  end

  test "returns the same materialized reference contract as the current binding-backed resolver" do
    context = create_workspace_context!
    default_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      user_agent_binding: context[:user_agent_binding],
      default_execution_runtime: context[:execution_runtime],
      name: "Default Workspace",
      is_default: true
    )

    expected = Workspaces::BuildDefaultReference.call(
      user_agent_binding: context[:user_agent_binding]
    )
    actual = Workspaces::ResolveDefaultReference.call(
      user: context[:user],
      agent: context[:agent]
    )

    assert_equal "materialized", actual.state
    assert_equal default_workspace.public_id, actual.workspace_id
    assert_equal expected.state, actual.state
    assert_equal expected.workspace_id, actual.workspace_id
    assert_equal expected.agent_id, actual.agent_id
    assert_equal expected.user_id, actual.user_id
    assert_equal expected.name, actual.name
    assert_equal expected.privacy, actual.privacy
    assert_equal expected.default_execution_runtime_id, actual.default_execution_runtime_id
  end
end
