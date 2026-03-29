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
  end

  private

  def create_conversation!
    context = create_workspace_context!
    Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
  end
end
