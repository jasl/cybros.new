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

  def test_stream_uses_native_messages_sse_and_yields_text_deltas
    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        attr_reader :last_request

        def call(_env)
          raise "stream should use call_stream"
        end

        def call_stream(env)
          @last_request = env

          sse = +""
          sse << %(event: message_start\n)
          sse << %(data: {"type":"message_start","message":{"id":"msg_123","type":"message","role":"assistant","content":[],"model":"claude-opus-4-1","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":2,"output_tokens":0}}}\n\n)
          sse << %(event: content_block_start\n)
          sse << %(data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n)
          sse << %(event: content_block_delta\n)
          sse << %(data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}\n\n)
          sse << %(event: content_block_delta\n)
          sse << %(data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}}\n\n)
          sse << %(event: content_block_stop\n)
          sse << %(data: {"type":"content_block_stop","index":0}\n\n)
          sse << %(event: message_delta\n)
          sse << %(data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":3}}\n\n)
          sse << %(event: message_stop\n)
          sse << %(data: {"type":"message_stop"}\n\n)

          yield sse

          {
            status: 200,
            headers: { "content-type" => "text/event-stream" },
            body: nil,
          }
        end
      end.new

    protocol = SimpleInference::Protocols::AnthropicMessages.new(base_url: "https://api.anthropic.com", api_key: "secret", adapter: adapter)
    events = protocol.stream(model: "claude-opus-4-1", input: "Hello").to_a

    assert_equal true, JSON.parse(adapter.last_request.fetch(:body)).fetch("stream")
    text_deltas = events.grep(SimpleInference::Responses::Events::TextDelta).map(&:delta)
    completed = events.find { |event| event.is_a?(SimpleInference::Responses::Events::Completed) }

    assert_equal ["Hel", "lo"], text_deltas
    refute_nil completed
    assert_equal "Hello", completed.result.output_text
    assert_equal 3, completed.result.usage.fetch("output_tokens")
  end
end
