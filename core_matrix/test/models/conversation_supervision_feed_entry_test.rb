require "test_helper"

class ConversationSupervisionFeedEntryTest < ActiveSupport::TestCase
  test "stores human-readable feed entries scoped to one conversation turn" do
    context = build_agent_control_context!

    entry = ConversationSupervisionFeedEntry.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      target_turn: context[:turn],
      sequence: 1,
      event_kind: "turn_todo_item_started",
      summary: "Started reviewing the board projection changes.",
      details_payload: {},
      occurred_at: Time.current
    )

    assert entry.public_id.present?
    assert_equal context[:conversation], entry.target_conversation
    assert_equal context[:turn], entry.target_turn
  end

  test "rejects duplicate sequence numbers per conversation and internal runtime tokens" do
    context = build_agent_control_context!
    ConversationSupervisionFeedEntry.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      target_turn: context[:turn],
      sequence: 1,
      event_kind: "turn_todo_item_started",
      summary: "Started the feed writer.",
      details_payload: {},
      occurred_at: Time.current
    )

    duplicate = ConversationSupervisionFeedEntry.new(
      installation: context[:installation],
      target_conversation: context[:conversation],
      target_turn: context[:turn],
      sequence: 1,
      event_kind: "progress_recorded",
      summary: "runtime.workflow_node leaked",
      details_payload: {},
      occurred_at: Time.current
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:sequence], "has already been taken"
    assert_includes duplicate.errors[:event_kind], "is not included in the list"
    assert_includes duplicate.errors[:summary], "must not expose internal runtime tokens"
  end
end
