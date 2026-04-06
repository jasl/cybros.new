require "test_helper"

class Conversations::Metadata::AgentUpdateTest < ActiveSupport::TestCase
  test "writes unlocked fields with agent source" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    occurred_at = Time.zone.parse("2026-04-06 11:10:00")

    Conversations::Metadata::AgentUpdate.call(
      conversation: conversation,
      title: "Agent title",
      summary: "Agent summary",
      occurred_at: occurred_at
    )

    conversation.reload
    assert_equal "Agent title", conversation.title
    assert_equal "Agent summary", conversation.summary
    assert_equal "agent", conversation.title_source
    assert_equal "agent", conversation.summary_source
    assert_equal occurred_at, conversation.title_updated_at
    assert_equal occurred_at, conversation.summary_updated_at
  end

  test "rejects updates to locked fields" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    conversation.update!(
      title: "Pinned title",
      title_source: "user",
      title_lock_state: "user_locked"
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Metadata::AgentUpdate.call(
        conversation: conversation,
        title: "Agent override attempt"
      )
    end

    assert_includes error.record.errors[:title], "is locked by user"
    conversation.reload
    assert_equal "Pinned title", conversation.title
    assert_equal "user", conversation.title_source
    assert_equal "user_locked", conversation.title_lock_state
  end

  private

  def fresh_workspace_context!
    Installation.destroy_all
    create_workspace_context!
  end
end
