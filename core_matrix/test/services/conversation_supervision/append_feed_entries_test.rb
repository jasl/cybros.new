require "test_helper"

class ConversationSupervision::AppendFeedEntriesTest < ActiveSupport::TestCase
  test "appends semantic feed entries for the active turn in sequence order" do
    context = build_agent_control_context!

    entries = ConversationSupervision::AppendFeedEntries.call(
      conversation: context[:conversation],
      changeset: [
        {
          "event_kind" => "turn_started",
          "summary" => "Started the turn.",
          "details_payload" => { "overall_state" => "queued" },
        },
        {
          "event_kind" => "turn_todo_item_started",
          "summary" => "Started the new supervision schema.",
          "details_payload" => { "current_item_key" => "schema" },
        },
      ],
      occurred_at: Time.current
    )

    assert_equal [1, 2], entries.map(&:sequence)
    assert_equal [context[:turn].id, context[:turn].id], entries.map(&:target_turn_id)
    assert_equal %w[turn_started turn_todo_item_started], entries.map(&:event_kind)
  end
end
