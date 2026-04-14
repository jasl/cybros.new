# frozen_string_literal: true

require "json"
require "test_helper"

class TestOpenAIImagesProtocol < Minitest::Test
  def test_generate_normalizes_openai_image_payload
    adapter = Class.new(SimpleInference::HTTPAdapter) do
      attr_reader :last_request

      def call(env)
        @last_request = env

        {
          status: 200,
          headers: { "content-type" => "application/json" },
          body: JSON.generate(
            {
              data: [
                {
                  b64_json: "aGVsbG8=",
                  revised_prompt: "hello image",
                },
              ],
            }
          ),
        }
      end
    end.new

    protocol = SimpleInference::Protocols::OpenAIImages.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    result = protocol.generate(model: "gpt-image-1", prompt: "hello")

    assert_instance_of SimpleInference::Images::Result, result
    assert_equal "aGVsbG8=", result.images.fetch(0).fetch("b64_json")
    assert_equal "data:image/png;base64,aGVsbG8=", result.images.fetch(0).fetch("data_url")
    assert_equal "http://example.com/v1/images/generations", adapter.last_request.fetch(:url)
  end
end
