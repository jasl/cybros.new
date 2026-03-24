require "test_helper"

class ConversationStructureFlowTest < ActionDispatch::IntegrationTest
  test "interactive conversations support lineage while automation stays root only" do
    workspace = create_workspace_context![:workspace]

    root = Conversations::CreateRoot.call(workspace: workspace)
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: 101
    )
    thread = Conversations::CreateThread.call(parent: root)
    checkpoint = Conversations::CreateCheckpoint.call(
      parent: branch,
      historical_anchor_message_id: 303
    )

    Conversations::Archive.call(conversation: branch)
    Conversations::Unarchive.call(conversation: branch)

    automation_root = Conversations::CreateAutomationRoot.call(workspace: workspace)

    assert_equal "active", branch.reload.lifecycle_state
    assert_equal [[root.id, checkpoint.id, 2], [branch.id, checkpoint.id, 1], [checkpoint.id, checkpoint.id, 0]],
      ConversationClosure.where(descendant_conversation: checkpoint)
        .order(depth: :desc)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateBranch.call(
        parent: automation_root,
        historical_anchor_message_id: 404
      )
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateThread.call(parent: automation_root)
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateCheckpoint.call(
        parent: automation_root,
        historical_anchor_message_id: 505
      )
    end
  end
end
