require "test_helper"

class ConversationSupervisionFeedEntryTest < ActiveSupport::TestCase
  test "stores human-readable feed entries scoped to one conversation turn" do
    context = build_agent_control_context!

    entry = ConversationSupervisionFeedEntry.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      target_turn: context[:turn],
      user: context[:conversation].user,
      workspace: context[:conversation].workspace,
      agent: context[:conversation].agent,
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
      user: context[:conversation].user,
      workspace: context[:conversation].workspace,
      agent: context[:conversation].agent,
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
      user: context[:conversation].user,
      workspace: context[:conversation].workspace,
      agent: context[:conversation].agent,
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

  test "requires duplicated owner context to match the target conversation" do
    context = build_agent_control_context!
    foreign = create_workspace_context!

    entry = ConversationSupervisionFeedEntry.new(
      installation: context[:installation],
      target_conversation: context[:conversation],
      target_turn: context[:turn],
      user_id: foreign[:user].id,
      workspace_id: foreign[:workspace].id,
      agent_id: foreign[:agent].id,
      sequence: 1,
      event_kind: "turn_started",
      summary: "Started the turn.",
      details_payload: {},
      occurred_at: Time.current
    )

    assert_not entry.valid?
    assert_includes entry.errors[:user], "must match the target conversation user"
    assert_includes entry.errors[:workspace], "must match the target conversation workspace"
    assert_includes entry.errors[:agent], "must match the target conversation agent"
  end
end
