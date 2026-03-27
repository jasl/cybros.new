require "test_helper"

class ProviderRequestContextTest < ActiveSupport::TestCase
  test "round trips a valid provider request context contract" do
    context = ProviderRequestContext.new(
      "provider_handle" => "openai",
      "model_ref" => "gpt-5.4",
      "api_model" => "gpt-5.4",
      "wire_api" => "responses",
      "transport" => "https",
      "tokenizer_hint" => "o200k_base",
      "execution_settings" => { "reasoning_effort" => "high" },
      "hard_limits" => { "context_window_tokens" => 272_000, "max_output_tokens" => 128_000 },
      "advisory_hints" => { "recommended_compaction_threshold" => 217_600 },
      "provider_metadata" => {},
      "model_metadata" => {}
    )

    assert_equal "openai", context.provider_handle
    assert_equal "gpt-5.4", context.model_ref
    assert_equal "gpt-5.4", context.api_model
    assert_equal "responses", context.wire_api
    assert_equal "https", context.transport
    assert_equal "o200k_base", context.tokenizer_hint
    assert_equal({ "reasoning_effort" => "high" }, context.execution_settings)
    assert_equal(
      {
        "provider_handle" => "openai",
        "model_ref" => "gpt-5.4",
        "api_model" => "gpt-5.4",
        "wire_api" => "responses",
        "transport" => "https",
        "tokenizer_hint" => "o200k_base",
        "execution_settings" => { "reasoning_effort" => "high" },
        "hard_limits" => { "context_window_tokens" => 272_000, "max_output_tokens" => 128_000 },
        "advisory_hints" => { "recommended_compaction_threshold" => 217_600 },
        "provider_metadata" => {},
        "model_metadata" => {},
      },
      context.to_h
    )
  end

  test "rejects missing required fields" do
    error = assert_raises(ProviderRequestContext::InvalidContext) do
      ProviderRequestContext.new(
        "provider_handle" => "",
        "model_ref" => "gpt-5.4",
        "api_model" => "gpt-5.4",
        "wire_api" => "responses",
        "transport" => "https",
        "tokenizer_hint" => "o200k_base",
        "execution_settings" => {},
        "hard_limits" => {},
        "advisory_hints" => {},
        "provider_metadata" => {},
        "model_metadata" => {}
      )
    end

    assert_includes error.message, "provider_handle"
  end
end
