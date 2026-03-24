require "test_helper"

class Conversations::CreateThreadTest < ActiveSupport::TestCase
  test "creates a thread without requiring transcript cloning" do
    root = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])

    thread = Conversations::CreateThread.call(
      parent: root,
      historical_anchor_message_id: 202
    )

    assert thread.thread?
    assert thread.interactive?
    assert thread.active?
    assert_equal root, thread.parent_conversation
    assert_equal 202, thread.historical_anchor_message_id
    assert_equal [[root.id, thread.id, 1], [thread.id, thread.id, 0]],
      ConversationClosure.where(descendant_conversation: thread)
        .order(depth: :desc)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)
  end

  test "rejects automation conversations" do
    automation_root = Conversations::CreateAutomationRoot.call(
      workspace: create_workspace_context![:workspace]
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateThread.call(parent: automation_root)
    end
  end
end
