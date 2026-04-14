# frozen_string_literal: true

require "json"
require "test_helper"

class TestAnthropicProtocol < Minitest::Test
  def test_create_maps_messages_payload_into_responses_result
    adapter = Class.new(SimpleInference::HTTPAdapter) do
      attr_reader :last_request

      def call(env)
        @last_request = env

        {
          status: 200,
          headers: { "content-type" => "application/json" },
          body: JSON.generate(
            {
              id: "msg_123",
              content: [
                {
                  type: "text",
                  text: "Claude hello",
                },
                {
                  type: "tool_use",
                  id: "toolu_123",
                  name: "calculator",
                  input: {
                    expression: "2 + 2",
                  },
                },
              ],
              stop_reason: "end_turn",
              usage: {
                input_tokens: 2,
                output_tokens: 3,
              },
            }
          ),
        }
      end
    end.new

    protocol = SimpleInference::Protocols::AnthropicMessages.new(base_url: "https://api.anthropic.com", api_key: "secret", adapter: adapter)
    result = protocol.create(
      model: "claude-opus-4-1",
      input: [
        { role: "system", content: "Be terse" },
        { role: "user", content: "Hello" },
        {
          type: "function_call",
          call_id: "toolu_123",
          name: "calculator",
          arguments: "{\"expression\":\"2 + 2\"}",
        },
        {
          type: "function_call_output",
          call_id: "toolu_123",
          output: "{\"value\":4}",
        },
      ],
      tools: [
        {
          type: "function",
          name: "calculator",
          parameters: {
            type: "object",
            properties: {
              expression: { type: "string" },
            },
          },
        },
      ]
    )

    request_body = JSON.parse(adapter.last_request.fetch(:body))

    assert_instance_of SimpleInference::Responses::Result, result
    assert_equal "Claude hello", result.output_text
    assert_equal "responses", result.provider_format
    assert_equal "function_call", result.output_items.fetch(1).fetch("type")
    assert_equal "calculator", result.output_items.fetch(1).fetch("name")
    assert_equal "Be terse", request_body.fetch("system")
    assert_equal "Hello", request_body.fetch("messages").fetch(0).fetch("content").fetch(0).fetch("text")
    assert_equal "tool_use", request_body.fetch("messages").fetch(1).fetch("content").fetch(0).fetch("type")
    assert_equal "tool_result", request_body.fetch("messages").fetch(2).fetch("content").fetch(0).fetch("type")
    assert_equal "calculator", request_body.fetch("tools").fetch(0).fetch("name")
  end
end
