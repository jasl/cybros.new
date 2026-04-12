require "test_helper"

class Conversations::WithRetainedLifecycleLockTest < ActiveSupport::TestCase
  test "allows close in progress while the retained lifecycle contract still matches" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    ConversationCloseOperation.create!(
      installation: conversation.installation,
      conversation: conversation,
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    yielded = Conversations::WithRetainedLifecycleLock.call(
      conversation: conversation,
      record: conversation,
      retained_message: "must be retained before archival",
      expected_state: "active",
      lifecycle_message: "must be active before archival"
    ) do |current_conversation|
      current_conversation
    end

    assert_equal conversation.id, yielded.id
  end

  test "yields a retained conversation in the expected lifecycle state" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )

    yielded = Conversations::WithRetainedLifecycleLock.call(
      conversation: conversation,
      record: conversation,
      retained_message: "must be retained before archival",
      expected_state: "active",
      lifecycle_message: "must be active before archival"
    ) do |current_conversation|
      current_conversation
    end

    assert_equal conversation.id, yielded.id
    assert yielded.active?
  end

  test "rejects non-retained conversations before yielding" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::WithRetainedLifecycleLock.call(
        conversation: conversation,
        record: conversation,
        retained_message: "must be retained before archival",
        expected_state: "active",
        lifecycle_message: "must be active before archival"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before archival"
  end

  test "rejects conversations outside the expected lifecycle state before yielding" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    conversation.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::WithRetainedLifecycleLock.call(
        conversation: conversation,
        record: conversation,
        retained_message: "must be retained before archival",
        expected_state: "active",
        lifecycle_message: "must be active before archival"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before archival"
  end
end
