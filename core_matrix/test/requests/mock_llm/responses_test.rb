require "test_helper"

class MockLLMResponsesTest < ActionDispatch::IntegrationTest
  test "returns an openai shaped responses payload" do
    post "/mock_llm/v1/responses", params: {
      model: "mock-model",
      input: [
        {
          role: "user",
          content: [
            { type: "input_text", text: "!md hello" },
          ],
        },
      ],
    }, as: :json

    assert_response :success
    assert_equal "response", response.parsed_body["object"]
    assert_equal "completed", response.parsed_body["status"]
    assert_match "# Mock Markdown", response.parsed_body.dig("output", 0, "content", 0, "text")
  end

  test "streams responses delta events" do
    post "/mock_llm/v1/responses", params: {
      model: "mock-model",
      input: "hello",
      stream: true,
    }, as: :json

    assert_response :success
    assert_includes response.body, "\"type\":\"response.output_text.delta\""
    assert_includes response.body, "\"type\":\"response.completed\""
    assert_includes response.body, "data: [DONE]"
  end
end
