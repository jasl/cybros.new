require "test_helper"

class Fenix::Hooks::RuntimeHooksTest < ActiveSupport::TestCase
  test "estimate helpers provide stable advisory counts" do
    messages = [
      { "role" => "system", "content" => "You are Fenix." },
      { "role" => "user", "content" => "Summarize this request." },
    ]

    assert_equal 2, Fenix::Hooks::EstimateMessages.call(messages: messages)
    assert_operator Fenix::Hooks::EstimateTokens.call(messages: messages), :>, 0
  end

  test "review_tool_call rejects unsupported tool names" do
    error = assert_raises(Fenix::Hooks::ReviewToolCall::UnsupportedToolError) do
      Fenix::Hooks::ReviewToolCall.call(
        tool_call: { "tool_name" => "workspace_delete", "arguments" => {} },
        allowed_tool_names: %w[calculator]
      )
    end

    assert_match(/workspace_delete/, error.message)
  end

  test "review_tool_call rejects masked tool names" do
    error = assert_raises(Fenix::Hooks::ReviewToolCall::UnsupportedToolError) do
      Fenix::Hooks::ReviewToolCall.call(
        tool_call: { "tool_name" => "calculator", "arguments" => { "expression" => "2 + 2" } },
        allowed_tool_names: %w[compact_context]
      )
    end

    assert_match(/calculator/, error.message)
    assert_match(/not visible/, error.message)
  end

  test "handle_error produces a terminal failure payload" do
    payload = Fenix::Hooks::HandleError.call(
      error: StandardError.new("boom"),
      logical_work_id: "logical-work-1",
      attempt_no: 1
    )

    assert_equal "runtime_error", payload.fetch("failure_kind")
    assert_equal "boom", payload.fetch("last_error_summary")
    assert_equal false, payload.fetch("retryable")
  end
end
