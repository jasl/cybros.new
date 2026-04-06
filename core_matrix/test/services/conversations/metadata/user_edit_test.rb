require "test_helper"

class Conversations::Metadata::UserEditTest < ActiveSupport::TestCase
  test "editing title sets user source and lock without locking summary" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    occurred_at = Time.zone.parse("2026-04-06 11:00:00")

    Conversations::Metadata::UserEdit.call(
      conversation: conversation,
      title: "Pinned by user",
      occurred_at: occurred_at
    )

    conversation.reload
    assert_equal "Pinned by user", conversation.title
    assert_equal "user", conversation.title_source
    assert_equal "user_locked", conversation.title_lock_state
    assert_equal occurred_at, conversation.title_updated_at
    assert_equal "none", conversation.summary_source
    assert_equal "unlocked", conversation.summary_lock_state
  end

  test "editing summary sets user source and lock without locking title" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    occurred_at = Time.zone.parse("2026-04-06 11:05:00")

    Conversations::Metadata::UserEdit.call(
      conversation: conversation,
      summary: "User-authored summary",
      occurred_at: occurred_at
    )

    conversation.reload
    assert_equal "User-authored summary", conversation.summary
    assert_equal "user", conversation.summary_source
    assert_equal "user_locked", conversation.summary_lock_state
    assert_equal occurred_at, conversation.summary_updated_at
    assert_equal "none", conversation.title_source
    assert_equal "unlocked", conversation.title_lock_state
  end

  private

  def fresh_workspace_context!
    delete_all_table_rows!
    create_workspace_context!
  end
end
