require "test_helper"

class MockLLMImagesTest < ActionDispatch::IntegrationTest
  test "returns a deterministic image generation payload" do
    post "/mock_llm/v1/images/generations", params: {
      model: "mock-image-model",
      prompt: "hello image",
    }, as: :json

    assert_response :success
    assert_equal "hello image", response.parsed_body.dig("data", 0, "revised_prompt")
    assert response.parsed_body.dig("data", 0, "b64_json").present?
  end
end
