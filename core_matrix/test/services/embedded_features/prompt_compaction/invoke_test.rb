require "test_helper"

class EmbeddedFeatures::PromptCompaction::InvokeTest < ActiveSupport::TestCase
  test "returns an embedded prompt compaction artifact payload" do
    result = EmbeddedFeatures::PromptCompaction::Invoke.call(
      request_payload: {
        "selected_input_message_id" => "msg-current",
        "candidate_messages" => [
          { "role" => "system", "content" => "You are a coding agent." },
          { "role" => "user", "content" => "Review /tmp/report.json and app/models/user.rb." * 8 },
          { "role" => "user", "content" => "Newest input must stay verbatim." },
        ],
        "budget_hints" => {
          "hard_input_token_limit" => 80,
          "recommended_compaction_threshold" => 40,
        },
      }
    )

    assert_equal "prompt_compaction_context", result.fetch("artifact_kind")
    assert_equal "embedded", result.fetch("source")
    assert_equal true, result.fetch("compacted")
    assert_equal "msg-current", result.fetch("selected_input_message_id")
    assert_equal "Newest input must stay verbatim.", result.fetch("messages").last.fetch("content")
    assert_operator result.dig("before_estimate", "estimated_tokens"), :>, result.dig("after_estimate", "estimated_tokens")
  end
end
