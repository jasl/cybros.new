# frozen_string_literal: true

require_relative "openai_compatible"

module SimpleInference
  module Protocols
    class OpenRouterImages < OpenAICompatible
      def initialize(options = {})
        super
        opts = options.is_a?(Hash) ? options : {}
        @chat_path = opts[:responses_path] || opts["responses_path"] || "#{config.api_prefix}/chat/completions"
      end

      def generate(model:, prompt: nil, input: nil, modalities: nil, **params)
        raise SimpleInference::ValidationError, "model is required" if model.nil? || model.to_s.strip.empty?
        raise SimpleInference::ValidationError, "prompt or input is required" if prompt.to_s.strip.empty? && input.nil?

        response = post_json(
          @chat_path,
          {
            model: model,
            messages: [{ role: "user", content: prompt.to_s.strip.empty? ? input : prompt }],
            modalities: Array(modalities || %w[text image]),
          }.merge(params)
        )

        body = response.body.is_a?(Hash) ? response.body : {}
        message = body.dig("choices", 0, "message")

        SimpleInference::Images::Result.new(
          images: normalize_images(message),
          usage: body["usage"],
          provider_response: response,
          provider_format: "chat_completions",
          output_text: message.is_a?(Hash) ? message["content"] : nil
        )
      end

      private

      def normalize_images(message)
        return [] unless message.is_a?(Hash)

        Array(message["images"]).filter_map do |item|
          next unless item.is_a?(Hash)

          url = item.dig("image_url", "url") || item["url"]
          b64_json = item["b64_json"]
          mime_type = item["mime_type"] || "image/png"

          {
            "url" => url,
            "b64_json" => b64_json,
            "data_url" => b64_json ? "data:#{mime_type};base64,#{b64_json}" : nil,
            "mime_type" => mime_type,
            "raw" => item,
          }.compact
        end
      end
    end
  end
end
