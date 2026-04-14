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
                "provider_payload" => {
                  "vendor" => "openai",
                },
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
    provider_result = SimpleInference::Responses::Result.new(
      id: "chatcmpl_1",
      output_text: "",
      output_items: [],
      tool_calls: body.dig("choices", 0, "message", "tool_calls"),
      usage: { prompt_tokens: 3, completion_tokens: 1, total_tokens: 4 },
      finish_reason: "tool_calls",
      provider_response: SimpleInference::Response.new(
        status: 200,
        headers: {},
        body: body,
        raw_body: JSON.generate(body)
      ),
      provider_format: "chat_completions"
    )

    normalized = ProviderExecution::NormalizeProviderResponse.call(provider_result:)

    assert_equal "", normalized.fetch("output_text")
    assert_equal "tool_calls", normalized.fetch("finish_reason")
    assert_equal 1, normalized.fetch("tool_calls").length
    assert_equal "call_1", normalized.fetch("tool_calls").first.fetch("call_id")
    assert_equal "calculator", normalized.fetch("tool_calls").first.fetch("tool_name")
    assert_equal({ "expression" => "2 + 2" }, normalized.fetch("tool_calls").first.fetch("arguments"))
    assert_equal({ "vendor" => "openai" }, normalized.fetch("tool_calls").first.fetch("provider_payload"))
  end

  test "normalizes responses-api function_call output items into a shared shape" do
    request_context = ProviderRequestContext.new(
      "provider_handle" => "dev",
      "model_ref" => "mock-model",
      "api_model" => "mock-model",
      "wire_api" => "responses",
      "transport" => "http",
      "tokenizer_hint" => "o200k_base",
      "capabilities" => {},
      "execution_settings" => {},
      "hard_limits" => {},
      "advisory_hints" => {},
      "provider_metadata" => {
        "usage_capabilities" => {
          "prompt_cache_details" => false,
        },
      },
      "model_metadata" => {}
    )
    provider_result = SimpleInference::Responses::Result.new(
      id: "resp_1",
      output_text: "",
      output_items: [
        {
          "type" => "function_call",
          "id" => "item_1",
          "call_id" => "call_1",
          "name" => "workspace_write_file",
          "arguments" => "{\"path\":\"notes.txt\"}",
          "provider_payload" => {
            "thoughtSignature" => "sig_123",
          },
        },
      ],
      tool_calls: [],
      usage: { "input_tokens" => 5, "output_tokens" => 2, "total_tokens" => 7 },
      finish_reason: "completed",
      provider_response: nil,
      provider_format: "responses"
    )

    normalized = ProviderExecution::NormalizeProviderResponse.call(
      provider_result: provider_result,
      request_context: request_context
    )

    assert_equal "", normalized.fetch("output_text")
    assert_equal 1, normalized.fetch("tool_calls").length
    assert_equal "call_1", normalized.fetch("tool_calls").first.fetch("call_id")
    assert_equal "workspace_write_file", normalized.fetch("tool_calls").first.fetch("tool_name")
    assert_equal({ "path" => "notes.txt" }, normalized.fetch("tool_calls").first.fetch("arguments"))
    assert_equal({ "thoughtSignature" => "sig_123" }, normalized.fetch("tool_calls").first.fetch("provider_payload"))
    assert_equal(
      {
        "input_tokens" => 5,
        "output_tokens" => 2,
        "total_tokens" => 7,
        "prompt_cache_status" => "unsupported",
      },
      normalized.fetch("usage")
    )
  end
end
