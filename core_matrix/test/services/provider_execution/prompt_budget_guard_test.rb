require "test_helper"

class ProviderExecution::PromptBudgetGuardTest < ActiveSupport::TestCase
  test "returns allow when the candidate stays within the recommended threshold" do
    request_context = ProviderRequestContext.new(
      "provider_handle" => "dev",
      "model_ref" => "mock-model",
      "api_model" => "mock-model",
      "wire_api" => "chat_completions",
      "transport" => "https",
      "tokenizer_hint" => "o200k_base",
      "execution_settings" => {},
      "hard_limits" => {
        "hard_input_token_limit" => 120,
        "max_output_tokens" => 40,
      },
      "advisory_hints" => {
        "recommended_compaction_threshold" => 80,
      },
      "provider_metadata" => {},
      "model_metadata" => {},
    )

    result = ProviderExecution::PromptBudgetGuard.call(
      messages: [{ "role" => "user", "content" => "Short input" }],
      request_context: request_context,
      policy: { "strategy" => "runtime_first" }
    )

    assert_equal "allow", result.fetch("decision")
    assert_nil result["failure_scope"]
  end

  test "returns consult when the candidate exceeds the advisory threshold but still fits hard limits" do
    request_context = ProviderRequestContext.new(
      "provider_handle" => "dev",
      "model_ref" => "mock-model",
      "api_model" => "mock-model",
      "wire_api" => "chat_completions",
      "transport" => "https",
      "tokenizer_hint" => "o200k_base",
      "execution_settings" => {},
      "hard_limits" => {
        "hard_input_token_limit" => 120,
        "max_output_tokens" => 40,
      },
      "advisory_hints" => {
        "recommended_compaction_threshold" => 30,
      },
      "provider_metadata" => {},
      "model_metadata" => {},
    )

    result = ProviderExecution::PromptBudgetGuard.call(
      messages: [{ "role" => "user", "content" => "This message is deliberately long enough to cross the advisory threshold." * 2 }],
      request_context: request_context,
      policy: { "strategy" => "runtime_first" }
    )

    assert_equal "consult", result.fetch("decision")
    assert_nil result["failure_scope"]
  end

  test "returns compact_required when the candidate exceeds the hard limit but the latest input is still recoverable" do
    request_context = ProviderRequestContext.new(
      "provider_handle" => "dev",
      "model_ref" => "mock-model",
      "api_model" => "mock-model",
      "wire_api" => "chat_completions",
      "transport" => "https",
      "tokenizer_hint" => "o200k_base",
      "execution_settings" => {},
      "hard_limits" => {
        "hard_input_token_limit" => 80,
        "max_output_tokens" => 40,
      },
      "advisory_hints" => {
        "recommended_compaction_threshold" => 30,
      },
      "provider_metadata" => {},
      "model_metadata" => {},
    )

    result = ProviderExecution::PromptBudgetGuard.call(
      messages: [
        { "role" => "system", "content" => "You are a coding agent." },
        { "role" => "user", "content" => "Older context " * 50 },
        { "role" => "user", "content" => "Newest input" },
      ],
      request_context: request_context,
      policy: { "strategy" => "runtime_first" }
    )

    assert_equal "compact_required", result.fetch("decision")
    assert_nil result["failure_scope"]
  end

  test "returns reject when the latest input alone exceeds hard limits" do
    request_context = ProviderRequestContext.new(
      "provider_handle" => "dev",
      "model_ref" => "mock-model",
      "api_model" => "mock-model",
      "wire_api" => "chat_completions",
      "transport" => "https",
      "tokenizer_hint" => "o200k_base",
      "execution_settings" => {},
      "hard_limits" => {
        "hard_input_token_limit" => 20,
        "max_output_tokens" => 40,
      },
      "advisory_hints" => {
        "recommended_compaction_threshold" => 10,
      },
      "provider_metadata" => {},
      "model_metadata" => {},
    )

    result = ProviderExecution::PromptBudgetGuard.call(
      messages: [
        { "role" => "system", "content" => "You are a coding agent." },
        { "role" => "user", "content" => "A" * 400 },
      ],
      request_context: request_context,
      policy: { "strategy" => "runtime_first" }
    )

    assert_equal "reject", result.fetch("decision")
    assert_equal "current_input", result.fetch("failure_scope")
  end
end
