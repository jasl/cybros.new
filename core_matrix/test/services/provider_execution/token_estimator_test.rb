require "test_helper"

class ProviderExecution::TokenEstimatorTest < ActiveSupport::TestCase
  test "uses tiktoken for supported tokenizer hints" do
    result = ProviderExecution::TokenEstimator.call(
      input: [
        {
          "role" => "user",
          "content" => "Count the provider visible tokens in this draft.",
        },
      ],
      tokenizer_hint: "o200k_base"
    )

    assert_equal "tiktoken", result.fetch("strategy")
    assert_operator result.fetch("estimated_tokens"), :>, 0
    assert_equal 1, result.dig("diagnostics", "text_segments")
  end

  test "falls back to a multimodal heuristic when no exact tokenizer is available" do
    result = ProviderExecution::TokenEstimator.call(
      input: [
        {
          "role" => "user",
          "content" => [
            {
              "type" => "input_text",
              "text" => "Summarize this screenshot and keep the file refs.",
            },
            {
              "type" => "input_image",
              "image_url" => "https://example.test/screenshot.png",
            },
            {
              "type" => "input_file",
              "file_id" => "file-123",
            },
          ],
        },
      ],
      tokenizer_hint: "qwen3"
    )

    assert_equal "heuristic", result.fetch("strategy")
    assert_operator result.fetch("estimated_tokens"), :>, 0
    assert_equal ["file", "image", "text"], result.dig("diagnostics", "modalities").sort
  end
end
