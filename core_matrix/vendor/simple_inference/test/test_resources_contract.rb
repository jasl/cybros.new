# frozen_string_literal: true

require "json"
require "test_helper"

class TestResourcesContract < Minitest::Test
  class ResponsesAdapter < SimpleInference::HTTPAdapter
    attr_reader :requests

    def initialize
      @requests = []
    end

    def call(env)
      @requests << env

      body =
        {
          "id" => "resp_123",
          "output" => [
            {
              "type" => "message",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => "Hello from responses",
                },
              ],
            },
          ],
          "usage" => {
            "input_tokens" => 3,
            "output_tokens" => 4,
            "total_tokens" => 7,
          },
        }

      {
        status: 200,
        headers: { "content-type" => "application/json" },
        body: JSON.generate(body),
      }
    end
  end

  class ChatAdapter < SimpleInference::HTTPAdapter
    attr_reader :requests

    def initialize
      @requests = []
    end

    def call(env)
      @requests << env

      body =
        {
          "id" => "chatcmpl_123",
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => "Hello from chat",
              },
              "finish_reason" => "stop",
            },
          ],
          "usage" => {
            "prompt_tokens" => 2,
            "completion_tokens" => 3,
            "total_tokens" => 5,
          },
        }

      {
        status: 200,
        headers: { "content-type" => "application/json" },
        body: JSON.generate(body),
      }
    end
  end

  class ChatStreamingToolAdapter < SimpleInference::HTTPAdapter
    attr_reader :requests

    def initialize
      @requests = []
    end

    def call_stream(env)
      @requests << env

      chunks = [
        {
          "id" => "chatcmpl_stream_123",
          "object" => "chat.completion.chunk",
          "created" => 1,
          "model" => "openai/gpt-5.4",
          "choices" => [
            {
              "index" => 0,
              "delta" => {
                "role" => "assistant",
                "content" => "Need to run a command. ",
              },
              "finish_reason" => nil,
            },
          ],
        },
        {
          "id" => "chatcmpl_stream_123",
          "object" => "chat.completion.chunk",
          "created" => 1,
          "model" => "openai/gpt-5.4",
          "choices" => [
            {
              "index" => 0,
              "delta" => {
                "tool_calls" => [
                  {
                    "index" => 0,
                    "id" => "call_shell_1",
                    "type" => "function",
                    "function" => {
                      "name" => "exec_command",
                      "arguments" => "{\"command_line\":\"cd /workspace/game-2048 && npm test",
                    },
                  },
                ],
              },
              "finish_reason" => nil,
            },
          ],
        },
        {
          "id" => "chatcmpl_stream_123",
          "object" => "chat.completion.chunk",
          "created" => 1,
          "model" => "openai/gpt-5.4",
          "choices" => [
            {
              "index" => 0,
              "delta" => {
                "tool_calls" => [
                  {
                    "index" => 0,
                    "function" => {
                      "arguments" => " && npm run build\"}",
                    },
                  },
                ],
              },
              "finish_reason" => "tool_calls",
            },
          ],
          "usage" => {
            "prompt_tokens" => 3,
            "completion_tokens" => 4,
            "total_tokens" => 7,
          },
        },
      ]

      sse = +""
      chunks.each { |chunk| sse << "data: #{JSON.generate(chunk)}\n\n" }
      sse << "data: [DONE]\n\n"

      yield sse

      {
        status: 200,
        headers: { "content-type" => "text/event-stream" },
        body: nil,
      }
    end
  end

  def test_responses_create_uses_responses_protocol_for_responses_profiles
    adapter = ResponsesAdapter.new
    client = SimpleInference::Client.new(
      base_url: "http://example.com",
      api_key: "secret",
      adapter: adapter,
      provider_profile: {
        wire_api: "responses",
        responses_path: "/responses",
      }
    )

    result = client.responses.create(model: "gpt-5.4", input: "Hello")

    assert_instance_of SimpleInference::Responses::Result, result
    assert_equal "resp_123", result.id
    assert_equal "Hello from responses", result.output_text
    assert_equal 7, result.usage.fetch("total_tokens")

    request = adapter.requests.fetch(0)
    assert_equal :post, request.fetch(:method)
    assert_equal "http://example.com/responses", request.fetch(:url)
    assert_equal "gpt-5.4", JSON.parse(request.fetch(:body)).fetch("model")
  end

  def test_responses_create_falls_back_to_chat_protocol_for_chat_completions_profiles
    adapter = ChatAdapter.new
    client = SimpleInference::Client.new(
      base_url: "http://example.com",
      api_key: "secret",
      adapter: adapter,
      provider_profile: {
        wire_api: "chat_completions",
        responses_path: "/chat/completions",
      }
    )

    result = client.responses.create(model: "openai/gpt-5.4", input: "Hello")

    assert_instance_of SimpleInference::Responses::Result, result
    assert_equal "chatcmpl_123", result.id
    assert_equal "Hello from chat", result.output_text
    assert_equal 5, result.usage.fetch(:total_tokens)

    request = adapter.requests.fetch(0)
    assert_equal "http://example.com/v1/chat/completions", request.fetch(:url)
    assert_equal "Hello", JSON.parse(request.fetch(:body)).dig("messages", 0, "content")
  end

  def test_responses_create_routes_to_gemini_protocol_by_adapter_key
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
                      { text: "Hello from Gemini" },
                    ],
                  },
                  finishReason: "STOP",
                },
              ],
            }
          ),
        }
      end
    end.new

    client = SimpleInference::Client.new(
      base_url: "https://generativelanguage.googleapis.com",
      api_key: "secret",
      adapter: adapter,
      provider_profile: {
        adapter_key: "gemini_generate_content",
        wire_api: "responses",
      }
    )

    result = client.responses.create(model: "gemini-2.5-pro", input: "Hello")

    assert_equal "Hello from Gemini", result.output_text
    assert_equal "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent", adapter.last_request.fetch(:url)
  end

  def test_responses_create_routes_to_anthropic_protocol_by_adapter_key
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
                  text: "Hello from Claude",
                },
              ],
            }
          ),
        }
      end
    end.new

    client = SimpleInference::Client.new(
      base_url: "https://api.anthropic.com",
      api_key: "secret",
      adapter: adapter,
      provider_profile: {
        adapter_key: "anthropic_messages",
        wire_api: "responses",
      }
    )

    result = client.responses.create(model: "claude-opus-4-1", input: "Hello")

    assert_equal "Hello from Claude", result.output_text
    assert_equal "https://api.anthropic.com/v1/messages", adapter.last_request.fetch(:url)
  end

  def test_responses_stream_returns_stream_with_final_result
    adapter = Class.new(SimpleInference::HTTPAdapter) do
      def call_stream(_env)
        sse = +""
        sse << %(data: {"type":"response.output_text.delta","delta":"Hel"}\n\n)
        sse << %(data: {"type":"response.output_text.delta","delta":"lo"}\n\n)
        sse << %(data: {"type":"response.completed","response":{"id":"resp_stream","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3},"output":[{"type":"message","content":[{"type":"output_text","text":"Hello"}]}]}}\n\n)
        sse << "data: [DONE]\n\n"

        yield sse
        { status: 200, headers: { "content-type" => "text/event-stream" }, body: nil }
      end
    end.new

    client = SimpleInference::Client.new(
      base_url: "http://example.com",
      api_key: "secret",
      adapter: adapter,
      provider_profile: { wire_api: "responses", responses_path: "/responses" }
    )

    stream = client.responses.stream(model: "gpt-5.4", input: "Hello")
    event_types = stream.map(&:type)

    assert_includes event_types, "response.output_text.delta"
    assert_includes event_types, "response.completed"
    assert_equal "Hello", stream.get_output_text
    assert_equal "Hello", stream.get_final_result.output_text
  end

  def test_responses_stream_emits_tool_call_events_for_chat_completions_profiles
    adapter = ChatStreamingToolAdapter.new
    client = SimpleInference::Client.new(
      base_url: "http://example.com",
      api_key: "secret",
      adapter: adapter,
      provider_profile: {
        wire_api: "chat_completions",
      }
    )

    events = client.responses.stream(model: "openai/gpt-5.4", input: "Hello").to_a

    tool_delta = events.find { |event| event.is_a?(SimpleInference::Responses::Events::ToolCallDelta) }
    tool_done = events.find { |event| event.is_a?(SimpleInference::Responses::Events::ToolCallDone) }
    completed = events.find { |event| event.is_a?(SimpleInference::Responses::Events::Completed) }

    refute_nil tool_delta
    refute_nil tool_done
    refute_nil completed
    assert_equal "call_shell_1", tool_delta.call_id
    assert_equal "exec_command", tool_delta.name
    assert_equal "call_shell_1", tool_done.call_id
    assert_equal "exec_command", tool_done.name
    assert_equal "{\"command_line\":\"cd /workspace/game-2048 && npm test && npm run build\"}", tool_done.arguments
    assert_equal "Need to run a command. ", completed.result.output_text
    assert_equal "exec_command", completed.result.tool_calls.first.dig("function", "name")
  end

  def test_responses_create_rejects_builtin_tools_when_disabled_for_request
    client = SimpleInference::Client.new(
      base_url: "http://example.com",
      api_key: "secret",
      adapter: ResponsesAdapter.new,
      provider_profile: { wire_api: "responses", responses_path: "/responses" },
      model_profile: {
        capabilities: {
          tool_calls: true,
          provider_builtin_tools: true,
        },
      }
    )

    error =
      assert_raises(SimpleInference::CapabilityError) do
        client.responses.create(
          model: "gpt-5.4",
          input: "Hello",
          allow_builtin_tools: false,
          tools: [
            { type: "web_search_preview" },
          ]
        )
      end

    assert_includes error.message, "builtin tools are disabled"
  end

  def test_responses_create_rejects_image_input_when_model_profile_disables_it
    client = SimpleInference::Client.new(
      base_url: "http://example.com",
      api_key: "secret",
      adapter: ResponsesAdapter.new,
      provider_profile: { wire_api: "responses", responses_path: "/responses" },
      model_profile: {
        capabilities: {
          multimodal_inputs: {
            image: false,
          },
        },
      }
    )

    error =
      assert_raises(SimpleInference::CapabilityError) do
        client.responses.create(
          model: "gpt-5.4",
          input: [
            {
              role: "user",
              content: [
                { type: "input_image", image_url: "https://example.com/cat.png" },
              ],
            },
          ]
        )
      end

    assert_includes error.message, "image inputs are not enabled"
  end

  def test_responses_stream_rejects_when_streaming_is_disabled
    client = SimpleInference::Client.new(
      base_url: "http://example.com",
      api_key: "secret",
      adapter: ResponsesAdapter.new,
      provider_profile: { wire_api: "responses", responses_path: "/responses" },
      model_profile: {
        capabilities: {
          streaming: false,
        },
      }
    )

    error =
      assert_raises(SimpleInference::CapabilityError) do
        client.responses.stream(model: "gpt-5.4", input: "Hello")
      end

    assert_includes error.message, "responses.stream is not enabled"
  end

  def test_images_generate_rejects_when_request_disables_image_generation
    client = SimpleInference::Client.new(
      base_url: "http://example.com",
      api_key: "secret",
      adapter: ResponsesAdapter.new,
      provider_profile: { wire_api: "responses", responses_path: "/responses" },
      model_profile: {
        capabilities: {
          image_generation: true,
        },
      }
    )

    error =
      assert_raises(SimpleInference::CapabilityError) do
        client.images.generate(model: "gpt-image-1", prompt: "A sunset", allow_image_generation: false)
      end

    assert_includes error.message, "images.generate is disabled"
  end
end
