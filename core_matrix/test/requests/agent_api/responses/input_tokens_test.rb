require "test_helper"

class AgentApiResponsesInputTokensTest < ActionDispatch::IntegrationTest
  test "returns advisory token counts and budget hints for provider visible input" do
    context = build_governed_tool_context!

    post "/agent_api/responses/input_tokens",
      params: {
        provider_handle: "dev",
        model_ref: "mock-model",
        input: [
          {
            role: "user",
            content: "Count this provider-visible input.",
          },
        ],
      },
      headers: agent_api_headers(context.fetch(:agent_connection_credential)),
      as: :json

    assert_response :success

    body = JSON.parse(response.body)

    assert_equal "dev", body.fetch("provider_handle")
    assert_equal "mock-model", body.fetch("model_ref")
    assert_equal "o200k_base", body.fetch("tokenizer_hint")
    assert_operator body.fetch("estimated_tokens"), :>, 0
    assert_operator body.fetch("remaining_tokens"), :>=, 0
    assert_equal 111_616, body.fetch("hard_input_token_limit")
    assert_equal 102_400, body.fetch("recommended_input_tokens")
    assert_equal 16_384, body.fetch("reserved_output_tokens")
    assert_includes %w[allow consult compact_required], body.fetch("decision_hint")
  end
end
