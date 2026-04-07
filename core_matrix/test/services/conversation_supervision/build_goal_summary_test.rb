require "test_helper"

class ConversationSupervision::BuildGoalSummaryTest < ActiveSupport::TestCase
  test "extracts the actionable repair goal instead of the acceptance harness preamble" do
    summary = ConversationSupervision::BuildGoalSummary.call(
      content: <<~PROMPT
        Your previous attempt did not satisfy the acceptance harness.
        Continue working in `/workspace/game-2048` and fix the existing app. Do not restart from scratch unless necessary.
        This is repair attempt 2 of 3.

        Observed problems:
        - host browser verification ran but its assertions failed
      PROMPT
    )

    assert_equal "Fix the existing app in /workspace/game-2048.", summary
  end
end
