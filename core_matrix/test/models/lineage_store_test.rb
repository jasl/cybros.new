require "test_helper"

class LineageStoreTest < ActiveSupport::TestCase
  test "requires the root conversation to match workspace" do
    context = create_workspace_context!
    other_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      user_program_binding: context[:user_program_binding]
    )
    root_conversation = create_conversation_record!(workspace: context[:workspace])

    mismatched_workspace = LineageStore.new(
      installation: context[:installation],
      workspace: other_workspace,
      root_conversation: root_conversation
    )

    assert mismatched_workspace.invalid?
    assert_includes mismatched_workspace.errors[:workspace], "must match the root conversation workspace"
  end
end
