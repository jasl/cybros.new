require "test_helper"

class Conversations::ValidateMutableStateTest < ActiveSupport::TestCase
  test "returns the conversation when blocker snapshot allows live mutation" do
    conversation = create_conversation!

    validated = Conversations::ValidateMutableState.call(
      conversation: conversation,
      retained_message: "must be retained before mutating",
      active_message: "must be active before mutating",
      closing_message: "must not mutate while close is in progress"
    )

    assert_equal conversation.id, validated.id
  end

  test "rejects pending delete conversations with the supplied retained message" do
    conversation = create_conversation!
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ValidateMutableState.call(
        conversation: conversation,
        retained_message: "must be retained before mutating",
        active_message: "must be active before mutating",
        closing_message: "must not mutate while close is in progress"
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before mutating"
  end

  test "rejects archived conversations with the supplied active message" do
    conversation = create_conversation!
    conversation.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ValidateMutableState.call(
        conversation: conversation,
        retained_message: "must be retained before mutating",
        active_message: "must be active before mutating",
        closing_message: "must not mutate while close is in progress"
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before mutating"
  end

  test "rejects close in progress conversations with the supplied closing message" do
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
      Conversations::ValidateMutableState.call(
        conversation: conversation,
        retained_message: "must be retained before mutating",
        active_message: "must be active before mutating",
        closing_message: "must not mutate while close is in progress"
      )
    end

    assert_includes error.record.errors[:base], "must not mutate while close is in progress"
  end

  private

  def create_conversation!
    context = create_workspace_context!
    Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
  end
end
