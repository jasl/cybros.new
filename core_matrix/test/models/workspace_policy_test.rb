require "test_helper"

class WorkspacePolicyTest < ActiveSupport::TestCase
  test "requires one policy row per workspace and stores disabled capabilities as an array" do
    context = create_workspace_context!

    WorkspacePolicy.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      disabled_capabilities: ["control"]
    )

    duplicate = WorkspacePolicy.new(
      installation: context[:installation],
      workspace: context[:workspace],
      disabled_capabilities: []
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:workspace], "has already been taken"

    invalid = WorkspacePolicy.new(
      installation: context[:installation],
      workspace: create_workspace!(
        installation: context[:installation],
        user: context[:user],
        agent: context[:agent]
      ),
      disabled_capabilities: {}
    )

    assert_not invalid.valid?
    assert_includes invalid.errors[:disabled_capabilities], "must be an array"
  end
end
