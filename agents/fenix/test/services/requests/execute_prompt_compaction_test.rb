require "test_helper"

class Requests::ExecutePromptCompactionTest < ActiveSupport::TestCase
  test "returns a prompt compaction artifact that preserves the newest input" do
    response = Requests::ExecutePromptCompaction.call(
      payload: {
        "provider_context" => {
          "budget_hints" => {
            "hard_limits" => {
              "hard_input_token_limit" => 80,
            },
            "advisory_hints" => {
              "recommended_compaction_threshold" => 40,
            },
          },
        },
        "prompt_compaction" => {
          "consultation_reason" => "hard_limit",
          "selected_input_message_id" => "message-current",
          "candidate_messages" => [
            { "role" => "system", "content" => "You are a coding agent." },
            { "role" => "user", "content" => "Inspect /tmp/report.json and track ECONNRESET in app/models/user.rb." * 8 },
            { "role" => "user", "content" => "Newest input must stay verbatim." },
          ],
          "guard_result" => {
            "decision" => "compact_required",
            "estimated_tokens" => 144,
          },
        },
      }
    )

    assert_equal "ok", response.fetch("status")
    assert_equal "prompt_compaction_context", response.dig("artifact", "artifact_kind")
    assert_equal "runtime", response.dig("artifact", "source")
    assert_equal true, response.dig("artifact", "compacted")
    assert_equal "message-current", response.dig("artifact", "selected_input_message_id")
    assert_equal "Newest input must stay verbatim.", response.dig("artifact", "messages").last.fetch("content")
    assert_operator response.dig("artifact", "before_estimate", "estimated_tokens"), :>, response.dig("artifact", "after_estimate", "estimated_tokens")
  end
end
