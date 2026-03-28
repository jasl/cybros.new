require "test_helper"

class Turns::WithConversationEntryLockTest < ActiveSupport::TestCase
  test "yields an active retained conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    yielded = Turns::WithConversationEntryLock.call(
      conversation: conversation,
      entry_label: "user turn entry"
    ) do |current_conversation|
      current_conversation
    end

    assert_equal conversation.id, yielded.id
    assert yielded.active?
  end

  test "rejects pending delete conversations with entry label messaging" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::WithConversationEntryLock.call(
        conversation: conversation,
        entry_label: "follow up turn entry"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:deletion_state], "must be retained for follow up turn entry"
  end

  test "rejects archived conversations with entry label messaging" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    conversation.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::WithConversationEntryLock.call(
        conversation: conversation,
        entry_label: "automation turn entry"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active for automation turn entry"
  end

  test "rejects close in progress conversations with custom closing messaging" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    ConversationCloseOperation.create!(
      installation: conversation.installation,
      conversation: conversation,
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::WithConversationEntryLock.call(
        conversation: conversation,
        entry_label: "agent turn entry",
        closing_message: "must not accept agent turn entry while close is in progress"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:base], "must not accept agent turn entry while close is in progress"
  end
end
