require "test_helper"

class ProviderExecution::PromptBudgetAdvisoryTest < ActiveSupport::TestCase
  test "derives hard and advisory limits from model context" do
    advisory = ProviderExecution::PromptBudgetAdvisory.call(
      provider_handle: "dev",
      model_ref: "mock-model",
      api_model: "mock-model",
      tokenizer_hint: "o200k_base",
      context_window_tokens: 100,
      max_output_tokens: 40,
      context_soft_limit_ratio: 0.5
    )

    assert_equal 100, advisory.fetch("hard_context_limit")
    assert_equal 60, advisory.fetch("hard_input_token_limit")
    assert_equal 50, advisory.fetch("recommended_input_tokens")
    assert_equal 50, advisory.fetch("recommended_compaction_threshold")
    assert_equal 50, advisory.fetch("soft_threshold_tokens")
    assert_equal 50, advisory.fetch("reserved_tokens")
    assert_equal 40, advisory.fetch("reserved_output_tokens")
  end

  test "returns an advisory decision hint for a draft input candidate" do
    advisory = ProviderExecution::PromptBudgetAdvisory.call(
      provider_handle: "dev",
      model_ref: "mock-model",
      api_model: "mock-model",
      tokenizer_hint: "qwen3",
      context_window_tokens: 100,
      max_output_tokens: 40,
      context_soft_limit_ratio: 0.5,
      input: [
        {
          "role" => "user",
          "content" => "a" * 220,
        },
      ]
    )

    assert_equal "consult", advisory.fetch("decision_hint")
    assert_operator advisory.fetch("estimated_tokens"), :>, advisory.fetch("recommended_input_tokens")
    assert_operator advisory.fetch("estimated_tokens"), :<=, advisory.fetch("hard_input_token_limit")
  end
end
