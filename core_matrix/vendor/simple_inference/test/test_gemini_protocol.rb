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

  def test_stream_uses_stream_generate_content_sse_and_yields_text_deltas
    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        attr_reader :last_request

        def call(_env)
          raise "stream should use call_stream"
        end

        def call_stream(env)
          @last_request = env

          sse = +""
          sse << %(data: {"candidates":[{"content":{"parts":[{"text":"Hel"}]}}]}\n\n)
          sse << %(data: {"candidates":[{"content":{"parts":[{"text":"Hello"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":2,"candidatesTokenCount":3,"totalTokenCount":5}}\n\n)

          yield sse

          {
            status: 200,
            headers: { "content-type" => "text/event-stream" },
            body: nil,
          }
        end
      end.new

    protocol = SimpleInference::Protocols::GeminiGenerateContent.new(base_url: "https://generativelanguage.googleapis.com", api_key: "secret", adapter: adapter)
    events = protocol.stream(model: "gemini-2.5-pro", input: "Hello").to_a

    assert_includes adapter.last_request.fetch(:url), ":streamGenerateContent?alt=sse"
    text_deltas = events.grep(SimpleInference::Responses::Events::TextDelta).map(&:delta)
    completed = events.find { |event| event.is_a?(SimpleInference::Responses::Events::Completed) }

    assert_equal ["Hel", "lo"], text_deltas
    refute_nil completed
    assert_equal "Hello", completed.result.output_text
    assert_equal 5, completed.result.usage.fetch("total_tokens")
  end
end
