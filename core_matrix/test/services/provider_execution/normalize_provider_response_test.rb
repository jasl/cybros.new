require "test_helper"

class ProviderExecution::NormalizeProviderResponseTest < ActiveSupport::TestCase
  test "normalizes chat-completions tool calls into a shared shape" do
    body = {
      "choices" => [
        {
          "message" => {
            "tool_calls" => [
              {
                "id" => "call_1",
                "type" => "function",
                "function" => {
                  "name" => "calculator",
                  "arguments" => "{\"expression\":\"2 + 2\"}",
                },
              },
            ],
          },
          "finish_reason" => "tool_calls",
        },
      ],
    }
    provider_result = SimpleInference::OpenAI::ChatResult.new(
      content: "",
      usage: { prompt_tokens: 3, completion_tokens: 1, total_tokens: 4 },
      finish_reason: "tool_calls",
      response: SimpleInference::Response.new(
        status: 200,
        headers: {},
        body: body,
        raw_body: JSON.generate(body)
      )
    )

    normalized = ProviderExecution::NormalizeProviderResponse.call(provider_result:)

    assert_equal "", normalized.fetch("output_text")
    assert_equal "tool_calls", normalized.fetch("finish_reason")
    assert_equal 1, normalized.fetch("tool_calls").length
    assert_equal "call_1", normalized.fetch("tool_calls").first.fetch("call_id")
    assert_equal "calculator", normalized.fetch("tool_calls").first.fetch("tool_name")
    assert_equal({ "expression" => "2 + 2" }, normalized.fetch("tool_calls").first.fetch("arguments"))
  end

  test "normalizes responses-api function_call output items into a shared shape" do
    provider_result = SimpleInference::Protocols::OpenAIResponses::ResponsesResult.new(
      output_text: "",
      output_items: [
        {
          "type" => "function_call",
          "id" => "item_1",
          "call_id" => "call_1",
          "name" => "workspace_write_file",
          "arguments" => "{\"path\":\"notes.txt\"}",
        },
      ],
      usage: { "input_tokens" => 5, "output_tokens" => 2, "total_tokens" => 7 },
      response: nil
    )

    normalized = ProviderExecution::NormalizeProviderResponse.call(provider_result:)

    assert_equal "", normalized.fetch("output_text")
    assert_equal 1, normalized.fetch("tool_calls").length
    assert_equal "call_1", normalized.fetch("tool_calls").first.fetch("call_id")
    assert_equal "workspace_write_file", normalized.fetch("tool_calls").first.fetch("tool_name")
    assert_equal({ "path" => "notes.txt" }, normalized.fetch("tool_calls").first.fetch("arguments"))
    assert_equal 7, normalized.fetch("usage").fetch("total_tokens")
  end
end
