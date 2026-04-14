# frozen_string_literal: true

require "json"
require "test_helper"

class TestOpenRouterProtocols < Minitest::Test
  def test_responses_create_maps_chat_completions_payload_into_responses_result
    adapter = Class.new(SimpleInference::HTTPAdapter) do
      def call(_env)
        {
          status: 200,
          headers: { "content-type" => "application/json" },
          body: JSON.generate(
            {
              id: "chatcmpl_123",
              choices: [
                {
                  message: {
                    role: "assistant",
                    content: "OpenRouter hello",
                  },
                  finish_reason: "stop",
                },
              ],
              usage: {
                prompt_tokens: 2,
                completion_tokens: 3,
                total_tokens: 5,
              },
            }
          ),
        }
      end
    end.new

    protocol = SimpleInference::Protocols::OpenRouterResponses.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    result = protocol.create(model: "openai/gpt-5.4", input: "Hello")

    assert_instance_of SimpleInference::Responses::Result, result
    assert_equal "OpenRouter hello", result.output_text
    assert_equal "chat_completions", result.provider_format
  end

  def test_images_generate_normalizes_openrouter_message_images
    adapter = Class.new(SimpleInference::HTTPAdapter) do
      def call(_env)
        {
          status: 200,
          headers: { "content-type" => "application/json" },
          body: JSON.generate(
            {
              choices: [
                {
                  message: {
                    content: "Rendered image",
                    images: [
                      {
                        image_url: {
                          url: "https://example.com/image.png",
                        },
                      },
                    ],
                  },
                },
              ],
            }
          ),
        }
      end
    end.new

    protocol = SimpleInference::Protocols::OpenRouterImages.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    result = protocol.generate(model: "openai/gpt-5-image", prompt: "Hello")

    assert_instance_of SimpleInference::Images::Result, result
    assert_equal "https://example.com/image.png", result.images.fetch(0).fetch("url")
    assert_equal "Rendered image", result.output_text
  end
end
