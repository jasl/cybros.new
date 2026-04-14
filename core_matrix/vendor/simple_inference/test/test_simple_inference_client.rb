# frozen_string_literal: true

require "json"
require "test_helper"

class TestSimpleInferenceClient < Minitest::Test
  def test_client_exposes_resource_objects_and_not_chat_helpers
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret")

    assert_respond_to client, :responses
    assert_respond_to client, :images
    assert_respond_to client.responses, :create
    assert_respond_to client.responses, :stream
    assert_respond_to client.images, :generate
    refute_respond_to client, :chat
    refute_respond_to client, :chat_stream
  end

  def test_client_raises_configuration_error_for_invalid_headers_shape
    error =
      assert_raises(SimpleInference::ConfigurationError) do
        SimpleInference::Client.new(base_url: "http://example.com", headers: [])
      end

    assert_includes error.message, "headers"
  end

  def test_client_raises_configuration_error_for_invalid_options_shape
    error =
      assert_raises(SimpleInference::ConfigurationError) do
        SimpleInference::Client.new([])
      end

    assert_includes error.message, "options"
  end

  def test_client_raises_configuration_error_for_invalid_timeout_value
    error =
      assert_raises(SimpleInference::ConfigurationError) do
        SimpleInference::Client.new(base_url: "http://example.com", timeout: "oops")
      end

    assert_includes error.message, "timeout"
  end
end
