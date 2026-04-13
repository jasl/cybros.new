require "test_helper"

class LineageStoreTest < ActiveSupport::TestCase
  test "requires the owner conversation to match workspace" do
    context = create_workspace_context!
    other_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      agent: context[:agent]
    )
    owner_conversation = create_conversation_record!(workspace: context[:workspace])

    assert_nil LineageStore.reflect_on_association(:root_conversation)
    assert_not_nil LineageStore.reflect_on_association(:owner_conversation)

    mismatched_workspace = LineageStore.new(
      installation: context[:installation],
      workspace: other_workspace,
      owner_conversation: owner_conversation
    )

    assert mismatched_workspace.invalid?
    assert_includes mismatched_workspace.errors[:workspace], "must match the owner conversation workspace"
  end
end
