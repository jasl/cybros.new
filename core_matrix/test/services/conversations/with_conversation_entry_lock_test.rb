require "test_helper"

class Conversations::WithConversationEntryLockTest < ActiveSupport::TestCase
  test "yields an active retained conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )

    yielded = Conversations::WithConversationEntryLock.call(
      conversation: conversation,
      record: conversation,
      retained_message: "must be retained before adding imports",
      active_message: "must be active before adding imports",
      closing_message: "must not add imports while close is in progress"
    ) do |current_conversation|
      current_conversation
    end

    assert_equal conversation.id, yielded.id
    assert yielded.active?
  end

  test "rejects pending delete conversations with caller supplied retained messaging" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::WithConversationEntryLock.call(
        conversation: conversation,
        record: conversation,
        retained_message: "must be retained before adding imports",
        active_message: "must be active before adding imports",
        closing_message: "must not add imports while close is in progress"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before adding imports"
  end

  test "rejects archived conversations with caller supplied active messaging" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    conversation.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::WithConversationEntryLock.call(
        conversation: conversation,
        record: conversation,
        retained_message: "must be retained before checkpointing",
        active_message: "must be active before checkpointing",
        closing_message: "must not create child conversations while close is in progress"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before checkpointing"
  end

  test "rejects close in progress conversations with caller supplied closing messaging" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
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
      Conversations::WithConversationEntryLock.call(
        conversation: conversation,
        record: conversation,
        retained_message: "must be retained before checkpointing",
        active_message: "must be active before checkpointing",
        closing_message: "must not create child conversations while close is in progress"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:base], "must not create child conversations while close is in progress"
  end
end
