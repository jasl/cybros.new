# frozen_string_literal: true

require "json"
require "test_helper"

class TestGeminiProtocol < Minitest::Test
  def test_create_maps_generate_content_payload_into_responses_result
    adapter = Class.new(SimpleInference::HTTPAdapter) do
      attr_reader :last_request

      def call(env)
        @last_request = env

        {
          status: 200,
          headers: { "content-type" => "application/json" },
          body: JSON.generate(
            {
              candidates: [
                {
                  content: {
                    parts: [
                      { thoughtSignature: "sig_123", functionCall: { id: "call_123", name: "calculator", args: { expression: "2 + 2" } } },
                      { text: "Gemini hello" },
                    ],
                  },
                  finishReason: "STOP",
                },
              ],
              usageMetadata: {
                promptTokenCount: 2,
                candidatesTokenCount: 3,
                totalTokenCount: 5,
              },
            }
          ),
        }
      end
    end.new

    protocol = SimpleInference::Protocols::GeminiGenerateContent.new(base_url: "https://generativelanguage.googleapis.com", api_key: "secret", adapter: adapter)
    result = protocol.create(
      model: "gemini-2.5-pro",
      input: [
        { role: "system", content: "Be terse" },
        { role: "user", content: "Hello" },
        {
          type: "function_call",
          call_id: "call_123",
          name: "calculator",
          arguments: "{\"expression\":\"2 + 2\"}",
          provider_payload: {
            functionCall: {
              id: "call_123",
              name: "calculator",
              args: {
                expression: "2 + 2",
              },
            },
            thoughtSignature: "sig_123",
          },
        },
        {
          type: "function_call_output",
          call_id: "call_123",
          name: "calculator",
          output: "{\"value\":4}",
        },
      ],
      tools: [
        {
          type: "function",
          name: "calculator",
          description: "Solve arithmetic",
          parameters: {
            type: "object",
            properties: {
              expression: { type: "string" },
            },
          },
        },
        {
          type: "function",
          function: {
            name: "calculator",
            description: "Solve arithmetic again",
            parameters: {
              type: "object",
              properties: {
                expression: { type: "string" },
              },
            },
          },
        },
      ]
    )

    request_body = JSON.parse(adapter.last_request.fetch(:body))

    assert_instance_of SimpleInference::Responses::Result, result
    assert_equal "Gemini hello", result.output_text
    assert_equal 5, result.usage.fetch("total_tokens")
    assert_equal "responses", result.provider_format
    assert_equal "function_call", result.output_items.fetch(0).fetch("type")
    assert_equal "sig_123", result.output_items.fetch(0).fetch("provider_payload").fetch("thoughtSignature")
    assert_equal "Be terse", request_body.fetch("systemInstruction").fetch("parts").fetch(0).fetch("text")
    assert_equal "Hello", request_body.fetch("contents").fetch(0).fetch("parts").fetch(0).fetch("text")
    assert_equal "sig_123", request_body.fetch("contents").fetch(1).fetch("parts").fetch(0).fetch("thoughtSignature")
    assert_equal "calculator", request_body.fetch("contents").fetch(2).fetch("parts").fetch(0).fetch("functionResponse").fetch("name")
    assert_equal 2, request_body.fetch("tools").fetch(0).fetch("functionDeclarations").length
  end
end
