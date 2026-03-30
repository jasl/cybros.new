require "test_helper"

class Fenix::Runtime::PrepareRoundTest < ActiveSupport::TestCase
  test "returns prepared messages and profile-visible program tools" do
    result = Fenix::Runtime::PrepareRound.call(payload: shared_contract_fixture("core_matrix_fenix_prepare_round_v1"))

    assert_equal default_context_messages, result.fetch("messages")
    assert_equal "gpt-4.1-mini", result.fetch("likely_model")
    assert_equal %w[compact_context estimate_messages estimate_tokens calculator],
      result.fetch("program_tools").map { |entry| entry.fetch("tool_name") }
    assert_equal %w[prepare_turn compact_context], result.fetch("trace").map { |entry| entry.fetch("hook") }
  end

  test "appends prior tool results as tool-role messages before compaction" do
    payload = shared_contract_fixture("core_matrix_fenix_prepare_round_v1").merge(
      "prior_tool_results" => [
        {
          "tool_call_id" => "tool-call-1",
          "tool_name" => "calculator",
          "result" => { "value" => 4 },
        },
      ]
    )

    result = Fenix::Runtime::PrepareRound.call(payload:)

    assert_equal "tool", result.fetch("messages").last.fetch("role")
    assert_equal({ "value" => 4 }.to_json, result.fetch("messages").last.fetch("content"))
  end
end
