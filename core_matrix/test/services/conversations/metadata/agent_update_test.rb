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

  test "writes unlocked field when the other submitted field is locked" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    occurred_at = Time.zone.parse("2026-04-06 11:20:00")
    conversation.update!(
      title: "Pinned title",
      title_source: "user",
      title_lock_state: "user_locked",
      summary: "Old summary",
      summary_source: "generated",
      summary_lock_state: "unlocked"
    )

    Conversations::Metadata::AgentUpdate.call(
      conversation: conversation,
      title: "Agent should not overwrite title",
      summary: "Agent can refresh summary",
      occurred_at: occurred_at
    )

    conversation.reload
    assert_equal "Pinned title", conversation.title
    assert_equal "user", conversation.title_source
    assert_equal "user_locked", conversation.title_lock_state
    assert_equal "Agent can refresh summary", conversation.summary
    assert_equal "agent", conversation.summary_source
    assert_equal occurred_at, conversation.summary_updated_at
  end

  test "rejects content with long digits in id label context" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Metadata::AgentUpdate.call(
        conversation: conversation,
        title: "id: 1234567890123"
      )
    end

    assert_includes error.record.errors[:title], "contains internal metadata content"
    conversation.reload
    assert_nil conversation.title
  end

  test "rejects content with runtime-internal tokens including _id forms" do
    context = fresh_workspace_context!
    blocked_tokens = %w[
      workflow_run_id
      workflow_node_id
      agent_task_run_id
      tool_invocation_id
      subagent_session_id
      command_run_id
      process_run_id
    ]

    blocked_tokens.each do |token|
      conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

      error = assert_raises(ActiveRecord::RecordInvalid) do
        Conversations::Metadata::AgentUpdate.call(
          conversation: conversation,
          summary: "#{token} looked stale"
        )
      end

      assert_includes error.record.errors[:summary], "contains internal metadata content"
      conversation.reload
      assert_nil conversation.summary
    end
  end

  test "allows long numbers outside internal id context" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    occurred_at = Time.zone.parse("2026-04-06 11:30:00")

    Conversations::Metadata::AgentUpdate.call(
      conversation: conversation,
      summary: "Forecast rose to 1234567890123 credits this cycle",
      occurred_at: occurred_at
    )

    conversation.reload
    assert_equal "Forecast rose to 1234567890123 credits this cycle", conversation.summary
    assert_equal "agent", conversation.summary_source
    assert_equal occurred_at, conversation.summary_updated_at
  end

  private

  def fresh_workspace_context!
    Installation.destroy_all
    create_workspace_context!
  end
end
