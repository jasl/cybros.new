# frozen_string_literal: true

module SimpleInference
  module Resources
    class Images
      def initialize(client:)
        @client = client
      end

      def generate(model:, prompt: nil, input: nil, **_options)
        raise SimpleInference::ValidationError, "model is required" if model.nil? || model.to_s.strip.empty?
        raise SimpleInference::ValidationError, "prompt or input is required" if prompt.to_s.strip.empty? && input.nil?

        _options = @client.request_planner.prepare_images_request(options: _options)
        protocol = @client.request_planner.images_protocol
        protocol.generate(model: model, prompt: prompt, input: input, **_options)
      end
    end
  end
end
