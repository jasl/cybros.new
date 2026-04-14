# frozen_string_literal: true

require_relative "simple_inference/version"
require_relative "simple_inference/config"
require_relative "simple_inference/errors"
require_relative "simple_inference/http_adapter"
require_relative "simple_inference/response"
require_relative "simple_inference/openai"
require_relative "simple_inference/capabilities/provider_profile"
require_relative "simple_inference/capabilities/model_profile"
require_relative "simple_inference/planning/request_planner"
require_relative "simple_inference/responses/result"
require_relative "simple_inference/responses/stream"
require_relative "simple_inference/images/result"
require_relative "simple_inference/resources/responses"
require_relative "simple_inference/resources/images"
require_relative "simple_inference/protocols/base"
require_relative "simple_inference/protocols/openai_compatible"
require_relative "simple_inference/protocols/openai_compatible_responses"
require_relative "simple_inference/protocols/openai_responses"
require_relative "simple_inference/protocols/openai_images"
require_relative "simple_inference/protocols/openrouter_responses"
require_relative "simple_inference/protocols/openrouter_images"
require_relative "simple_inference/protocols/gemini_generate_content"
require_relative "simple_inference/protocols/anthropic_messages"
require_relative "simple_inference/client"

module SimpleInference
  class << self
    # Convenience constructor using RORO-style options hash.
    #
    # Example:
    #   client = SimpleInference.new(base_url: "...", api_key: "...")
    def new(options = {})
      Client.new(options)
    end
  end
end
