require "test_helper"

class MockLLMChatCompletionsTest < ActionDispatch::IntegrationTest
  test "returns deterministic markdown for md prompts" do
    post "/mock_llm/v1/chat/completions", params: {
      model: "mock-model",
      messages: [{ role: "user", content: "!md hello" }],
    }, as: :json

    assert_response :success
    assert_match "# Mock Markdown", response.parsed_body.dig("choices", 0, "message", "content")
    assert_equal "mock-model", response.parsed_body["model"]
  end

  test "treats a bare single digit prompt as a delayed shortcut" do
    post "/mock_llm/v1/chat/completions", params: {
      model: "mock-model",
      messages: [{ role: "user", content: "3" }],
    }, as: :json

    assert_response :success
    assert_match(/\AMock delayed 3s:/, response.parsed_body.dig("choices", 0, "message", "content"))
  end

  test "returns an openai shaped rate limit error payload for mock directives" do
    post "/mock_llm/v1/chat/completions", params: {
      model: "mock-model",
      messages: [{ role: "user", content: "!mock error=429 message=rate_limited -- hello" }],
    }, as: :json

    assert_response :too_many_requests
    assert_equal "rate_limited", response.parsed_body.dig("error", "message")
    assert_equal "rate_limit_error", response.parsed_body.dig("error", "type")
  end

  test "extracts prompt text from structured content parts" do
    post "/mock_llm/v1/chat/completions", params: {
      model: "vision-model",
      messages: [
        {
          role: "user",
          content: [
            { type: "input_text", text: "!md structured hello" },
            { type: "input_image", image_url: "data:image/png;base64,abc" },
          ],
        },
      ],
    }, as: :json

    assert_response :success
    assert_match "# Mock Markdown", response.parsed_body.dig("choices", 0, "message", "content")
  end
end
