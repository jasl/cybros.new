require "test_helper"

class ProviderExecution::PromptCompactionStrategyTest < ActiveSupport::TestCase
  test "preserves the newest selected input and summarizes older context when the threshold is exceeded" do
    messages = [
      { "role" => "system", "content" => "You are a coding agent. Preserve live file paths and active errors." },
      { "role" => "user", "content" => "Investigate BUG-123 in app/models/user.rb and compare it with /tmp/report.json." },
      { "role" => "assistant", "content" => "Earlier run hit ECONNRESET while reading /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/user.rb.\n" * 6 },
      { "role" => "user", "content" => "Keep /tmp/report.json and ECONNRESET in mind while fixing app/models/user.rb." },
    ]

    result = ProviderExecution::PromptCompactionStrategy.call(
      messages: messages,
      hard_input_token_limit: 120,
      recommended_compaction_threshold: 50,
      selected_input_message_id: "msg-current"
    )

    assert_equal true, result.fetch("compacted")
    assert_equal "msg-current", result.fetch("selected_input_message_id")
    assert_equal messages.first, result.fetch("messages").first
    assert_equal messages.last, result.fetch("messages").last
    assert_operator result.dig("before_estimate", "estimated_tokens"), :>, result.dig("after_estimate", "estimated_tokens")
    assert_includes result.fetch("messages").map { |entry| entry.fetch("role") }, "system"

    summary_message = result.fetch("messages")[1]

    assert_includes summary_message.fetch("content"), "app/models/user.rb"
    assert_includes summary_message.fetch("content"), "/tmp/report.json"
    assert_includes summary_message.fetch("content"), "ECONNRESET"
  end

  test "reports the latest input as unrecoverable when it alone exceeds the hard limit" do
    latest_input = "A" * 800
    result = ProviderExecution::PromptCompactionStrategy.call(
      messages: [
        { "role" => "system", "content" => "System prompt" },
        { "role" => "user", "content" => latest_input },
      ],
      hard_input_token_limit: 20,
      recommended_compaction_threshold: 10,
      selected_input_message_id: "msg-current"
    )

    assert_equal false, result.fetch("compacted")
    assert_equal "selected_input_exceeds_hard_limit", result.fetch("stop_reason")
    assert_equal "current_input", result.fetch("failure_scope")
    assert_equal latest_input, result.fetch("messages").last.fetch("content")
  end
end
