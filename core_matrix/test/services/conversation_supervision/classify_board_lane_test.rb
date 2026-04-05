require "test_helper"

class ConversationSupervision::ClassifyBoardLaneTest < ActiveSupport::TestCase
  test "maps structured supervision states into stable board lanes" do
    assert_equal "idle",
      ConversationSupervision::ClassifyBoardLane.call(
        overall_state: "idle",
        active_subagent_count: 0,
        retry_due_at: nil
      )
    assert_equal "queued",
      ConversationSupervision::ClassifyBoardLane.call(
        overall_state: "queued",
        active_subagent_count: 0,
        retry_due_at: nil
      )
    assert_equal "active",
      ConversationSupervision::ClassifyBoardLane.call(
        overall_state: "running",
        active_subagent_count: 0,
        retry_due_at: nil
      )
    assert_equal "handoff",
      ConversationSupervision::ClassifyBoardLane.call(
        overall_state: "waiting",
        active_subagent_count: 2,
        retry_due_at: nil
      )
    assert_equal "waiting",
      ConversationSupervision::ClassifyBoardLane.call(
        overall_state: "waiting",
        active_subagent_count: 0,
        retry_due_at: nil
      )
    assert_equal "blocked",
      ConversationSupervision::ClassifyBoardLane.call(
        overall_state: "blocked",
        active_subagent_count: 2,
        retry_due_at: 5.minutes.from_now
      )
    assert_equal "done",
      ConversationSupervision::ClassifyBoardLane.call(
        overall_state: "completed",
        active_subagent_count: 0,
        retry_due_at: nil
      )
    assert_equal "failed",
      ConversationSupervision::ClassifyBoardLane.call(
        overall_state: "failed",
        active_subagent_count: 0,
        retry_due_at: nil
      )
  end
end
