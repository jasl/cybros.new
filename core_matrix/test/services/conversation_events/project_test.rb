require "test_helper"

class ConversationEvents::ProjectTest < ActiveSupport::TestCase
  test "assigns projection sequence and stream revisions without creating transcript messages" do
    context = build_human_interaction_context!
    baseline_message_ids = context[:conversation].messages.order(:id).pluck(:id)

    plain = ConversationEvents::Project.call(
      conversation: context[:conversation],
      turn: context[:turn],
      event_kind: "runtime.status",
      payload: { "state" => "waiting" }
    )
    stream_first = ConversationEvents::Project.call(
      conversation: context[:conversation],
      event_kind: "runtime.status",
      stream_key: "status-card",
      payload: { "state" => "streaming" }
    )
    stream_second = ConversationEvents::Project.call(
      conversation: context[:conversation],
      event_kind: "runtime.status",
      stream_key: "status-card",
      payload: { "state" => "resolved" }
    )

    assert_equal [0, 1, 2], [plain, stream_first, stream_second].map(&:projection_sequence)
    assert_nil plain.stream_revision
    assert_equal [0, 1], [stream_first, stream_second].map(&:stream_revision)
    assert_equal baseline_message_ids, context[:conversation].messages.order(:id).pluck(:id)
    assert_equal [plain, stream_second], ConversationEvent.live_projection(conversation: context[:conversation])
  end
end
