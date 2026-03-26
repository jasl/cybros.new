require "test_helper"

class ConversationCloseOperationTest < ActiveSupport::TestCase
  test "requires completion timestamp only for terminal lifecycle states" do
    conversation = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])

    operation = ConversationCloseOperation.new(
      installation: conversation.installation,
      conversation: conversation,
      intent_kind: "archive",
      lifecycle_state: "completed",
      requested_at: Time.current,
      summary_payload: {}
    )

    assert_not operation.valid?
    assert_includes operation.errors[:completed_at], "must exist when close operation is terminal"

    operation.completed_at = Time.current

    assert operation.valid?
  end

  test "allows only one unfinished close operation per conversation" do
    conversation = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])
    ConversationCloseOperation.create!(
      installation: conversation.installation,
      conversation: conversation,
      intent_kind: "archive",
      lifecycle_state: "quiescing",
      requested_at: Time.current,
      summary_payload: {}
    )

    competing = ConversationCloseOperation.new(
      installation: conversation.installation,
      conversation: conversation,
      intent_kind: "delete",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    assert_not competing.valid?
    assert_includes competing.errors[:conversation], "already has an unfinished close operation"
  end
end
