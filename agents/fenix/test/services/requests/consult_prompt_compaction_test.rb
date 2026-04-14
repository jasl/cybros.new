require "test_helper"

class Requests::ConsultPromptCompactionTest < ActiveSupport::TestCase
  test "returns compact when the candidate exceeds the recommended threshold" do
    response = Requests::ConsultPromptCompaction.call(
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
          "consultation_reason" => "soft_threshold",
          "selected_input_message_id" => "message-current",
          "candidate_messages" => [
            { "role" => "system", "content" => "You are a coding agent." },
            { "role" => "user", "content" => "Inspect /tmp/report.json and track ECONNRESET in app/models/user.rb." * 8 },
            { "role" => "user", "content" => "Newest input must stay verbatim." },
          ],
          "guard_result" => {
            "decision" => "consult",
            "estimated_tokens" => 144,
          },
        },
      }
    )

    assert_equal "ok", response.fetch("status")
    assert_equal "compact", response.fetch("decision")
    assert_equal "message-current", response.fetch("selected_input_message_id")
    assert_includes response.fetch("preservation_invariants"), "newest_selected_input_verbatim"
    assert_includes response.dig("diagnostics", "important_paths"), "/tmp/report.json"
    assert_includes response.dig("diagnostics", "important_tokens"), "ECONNRESET"
  end

  test "returns reject when the newest input alone exceeds the hard limit" do
    response = Requests::ConsultPromptCompaction.call(
      payload: {
        "provider_context" => {
          "budget_hints" => {
            "hard_limits" => {
              "hard_input_token_limit" => 20,
            },
            "advisory_hints" => {
              "recommended_compaction_threshold" => 10,
            },
          },
        },
        "prompt_compaction" => {
          "consultation_reason" => "hard_limit",
          "selected_input_message_id" => "message-current",
          "candidate_messages" => [
            { "role" => "system", "content" => "System prompt" },
            { "role" => "user", "content" => "A" * 400 },
          ],
          "guard_result" => {
            "decision" => "compact_required",
            "failure_scope" => "current_input",
          },
        },
      }
    )

    assert_equal "ok", response.fetch("status")
    assert_equal "reject", response.fetch("decision")
    assert_equal "current_input", response.dig("diagnostics", "failure_scope")
  end
end
