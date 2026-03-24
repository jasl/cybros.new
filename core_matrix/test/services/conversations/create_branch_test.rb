require "test_helper"

class Conversations::CreateBranchTest < ActiveSupport::TestCase
  test "requires a historical anchor and preserves lineage" do
    root = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateBranch.call(parent: root)
    end

    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: 101
    )

    assert branch.branch?
    assert branch.interactive?
    assert branch.active?
    assert_equal root, branch.parent_conversation
    assert_equal 101, branch.historical_anchor_message_id
    assert_equal [[root.id, branch.id, 1], [branch.id, branch.id, 0]],
      ConversationClosure.where(descendant_conversation: branch)
        .order(depth: :desc)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)
  end

  test "rejects automation conversations" do
    automation_root = Conversations::CreateAutomationRoot.call(
      workspace: create_workspace_context![:workspace]
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateBranch.call(
        parent: automation_root,
        historical_anchor_message_id: 101
      )
    end
  end
end
