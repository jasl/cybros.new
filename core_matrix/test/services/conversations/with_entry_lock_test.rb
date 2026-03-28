require "test_helper"

class Conversations::WithEntryLockTest < ActiveSupport::TestCase
  test "yields an active retained conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    yielded = Conversations::WithEntryLock.call(
      conversation: conversation,
      record: conversation,
      entry_label: "adding imports",
      closing_action: "add imports"
    ) do |current_conversation|
      current_conversation
    end

    assert_equal conversation.id, yielded.id
    assert yielded.active?
  end

  test "rejects pending delete conversations with entry messages" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::WithEntryLock.call(
        conversation: conversation,
        record: conversation,
        entry_label: "adding imports",
        closing_action: "add imports"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before adding imports"
  end

  test "rejects archived conversations with entry messages" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    conversation.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::WithEntryLock.call(
        conversation: conversation,
        record: conversation,
        entry_label: "updating overrides",
        closing_action: "update overrides"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before updating overrides"
  end

  test "rejects conversations while close is in progress with action-specific messaging" do
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
      Conversations::WithEntryLock.call(
        conversation: conversation,
        record: conversation,
        entry_label: "adding imports",
        closing_action: "add imports"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:base], "must not add imports while close is in progress"
  end
end
