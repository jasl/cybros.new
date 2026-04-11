require "test_helper"

class Conversations::ValidateRetainedStateTest < ActiveSupport::TestCase
  test "reloads persisted conversations before validating retained state" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    stale_conversation = Conversation.find(conversation.id)
    deleted_at = Time.zone.parse("2026-03-29 15:00:00 UTC")
    Conversation.find(conversation.id).update!(
      deletion_state: "pending_delete",
      deleted_at: deleted_at
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ValidateRetainedState.call(
        conversation: stale_conversation,
        message: "must be retained before mutating"
      )
    end

    assert_same stale_conversation, error.record
    assert_includes error.record.errors[:deletion_state], "must be retained before mutating"
  end

  test "returns the conversation when it is retained" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )

    assert_equal conversation, Conversations::ValidateRetainedState.call(
      conversation: conversation,
      message: "must be retained before mutating"
    )
  end
end
