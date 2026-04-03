require "test_helper"

class Conversations::RequestCloseTest < ActiveSupport::TestCase
  test "archive intent rejects conversations that are not retained" do
    conversation = create_conversation!
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::RequestClose.call(
        conversation: conversation,
        intent_kind: "archive"
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before archival"
  end

  test "delete intent preserves lifecycle state while marking the conversation pending delete" do
    conversation = create_conversation!
    conversation.update!(lifecycle_state: "archived")

    closed = Conversations::RequestClose.call(
      conversation: conversation,
      intent_kind: "delete",
      occurred_at: Time.zone.parse("2026-03-29 08:00:00 UTC")
    )

    close_operation = closed.reload.conversation_close_operations.order(:created_at).last

    assert closed.pending_delete?
    assert closed.archived?
    assert_equal "delete", close_operation.intent_kind
    assert_equal Time.zone.parse("2026-03-29 08:00:00 UTC"), close_operation.requested_at
    assert_equal Time.zone.parse("2026-03-29 08:00:00 UTC"), closed.deleted_at
  end

  test "rejects switching intent while a close operation is unfinished" do
    conversation = create_conversation!
    ConversationCloseOperation.create!(
      installation: conversation.installation,
      conversation: conversation,
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::RequestClose.call(
        conversation: conversation,
        intent_kind: "delete"
      )
    end

    assert_includes error.record.errors[:intent_kind], "must not change while a close operation is unfinished"
  end

  test "reuses the existing close operation when the same intent is retried" do
    conversation = create_conversation!
    occurred_at = Time.zone.parse("2026-03-29 08:00:00 UTC")

    first = Conversations::RequestClose.call(
      conversation: conversation,
      intent_kind: "delete",
      occurred_at: occurred_at
    )
    second = Conversations::RequestClose.call(
      conversation: conversation.reload,
      intent_kind: "delete",
      occurred_at: occurred_at + 5.minutes
    )

    close_operation = second.reload.conversation_close_operations.order(:created_at).last

    assert_equal first.deleted_at, second.deleted_at
    assert_equal 1, second.conversation_close_operations.count
    assert_equal "delete", close_operation.intent_kind
    assert_equal occurred_at, close_operation.requested_at
  end

  private

  def create_conversation!
    context = create_workspace_context!
    Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
  end
end
