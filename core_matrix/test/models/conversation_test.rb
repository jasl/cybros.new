require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  test "belongs to workspace and not directly to an agent installation" do
    assert_equal :belongs_to, Conversation.reflect_on_association(:workspace).macro
    assert_nil Conversation.reflect_on_association(:agent_installation)
    assert_not_includes Conversation.column_names, "agent_installation_id"
  end

  test "enforces conversation kind rules" do
    context = create_workspace_context!

    root = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )
    branch_without_parent = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      kind: "branch",
      purpose: "interactive",
      lifecycle_state: "active",
      historical_anchor_message_id: 101
    )
    checkpoint_without_anchor = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      kind: "checkpoint",
      purpose: "interactive",
      lifecycle_state: "active",
      parent_conversation: root
    )

    assert root.valid?
    assert_not branch_without_parent.valid?
    assert_includes branch_without_parent.errors[:parent_conversation], "must exist"
    assert_not checkpoint_without_anchor.valid?
    assert_includes checkpoint_without_anchor.errors[:historical_anchor_message_id], "must exist"
  end

  test "enforces automation conversations as root only" do
    context = create_workspace_context!

    automation_root = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      kind: "root",
      purpose: "automation",
      lifecycle_state: "active"
    )
    automation_branch = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      kind: "branch",
      purpose: "automation",
      lifecycle_state: "active",
      parent_conversation: automation_root,
      historical_anchor_message_id: 101
    )

    assert automation_root.valid?
    assert_not automation_branch.valid?
    assert_includes automation_branch.errors[:kind], "must be root for automation conversations"
  end

  test "requires child conversations to stay in the parent workspace" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(workspace: context[:workspace])
    other_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      user_agent_binding: context[:user_agent_binding],
      name: "Other Workspace"
    )

    child = Conversation.new(
      installation: context[:installation],
      workspace: other_workspace,
      parent_conversation: root,
      kind: "thread",
      purpose: "interactive",
      lifecycle_state: "active"
    )

    assert_not child.valid?
    assert_includes child.errors[:workspace], "must match the parent conversation workspace"
  end
end
