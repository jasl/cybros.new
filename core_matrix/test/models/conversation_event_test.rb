require "test_helper"

class ConversationEventTest < ActiveSupport::TestCase
  test "keeps stable projection ordering and collapses replaceable live streams" do
    context = build_human_interaction_context!
    baseline_message_ids = context[:conversation].messages.order(:id).pluck(:id)

    opened = ConversationEvent.create!(
      installation: context[:installation],
      conversation: context[:conversation],
      turn: context[:turn],
      projection_sequence: 0,
      event_kind: "human_interaction.opened",
      payload: { "state" => "open" }
    )
    streamed = ConversationEvent.create!(
      installation: context[:installation],
      conversation: context[:conversation],
      projection_sequence: 1,
      event_kind: "runtime.status",
      stream_key: "status-card",
      stream_revision: 0,
      payload: { "state" => "waiting" }
    )
    streamed_revision = ConversationEvent.create!(
      installation: context[:installation],
      conversation: context[:conversation],
      projection_sequence: 2,
      event_kind: "runtime.status",
      stream_key: "status-card",
      stream_revision: 1,
      payload: { "state" => "resolved" }
    )

    assert_equal [opened, streamed, streamed_revision], ConversationEvent.where(conversation: context[:conversation]).order(:projection_sequence).to_a
    assert_equal [opened, streamed_revision], ConversationEvent.live_projection(conversation: context[:conversation])
    assert_equal baseline_message_ids, context[:conversation].messages.order(:id).pluck(:id)

    duplicate_sequence = ConversationEvent.new(
      installation: context[:installation],
      conversation: context[:conversation],
      projection_sequence: 2,
      event_kind: "runtime.status",
      payload: {}
    )

    assert_not duplicate_sequence.valid?
    assert_includes duplicate_sequence.errors[:projection_sequence], "has already been taken"
  end
end
