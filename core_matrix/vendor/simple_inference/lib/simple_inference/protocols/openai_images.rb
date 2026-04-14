# frozen_string_literal: true

require_relative "base"

module SimpleInference
  module Protocols
    class OpenAIImages < Base
      def initialize(options = {})
        super
        opts = options.is_a?(Hash) ? options : {}
        @images_path = opts[:images_path] || opts["images_path"] || "#{config.api_prefix}/images/generations"
      end

      def generate(model:, prompt: nil, input: nil, **params)
        raise SimpleInference::ValidationError, "model is required" if model.nil? || model.to_s.strip.empty?
        raise SimpleInference::ValidationError, "prompt or input is required" if prompt.to_s.strip.empty? && input.nil?

        request = { model: model }.merge(params)
        request[:prompt] = prompt unless prompt.to_s.strip.empty?
        request[:input] = input unless input.nil?
        request[:prompt] = input if request[:prompt].nil? && input.is_a?(String)

        response = request_json(
          method: :post,
          url: "#{config.base_url}#{@images_path}",
          headers: config.headers,
          body: request,
          expect_json: true,
          raise_on_http_error: nil
        )

        body = response.body.is_a?(Hash) ? response.body : {}

        SimpleInference::Images::Result.new(
          images: normalize_images(body["data"]),
          usage: body["usage"],
          provider_response: response,
          provider_format: "images.generate",
          output_text: Array(body["data"]).filter_map { |item| item.is_a?(Hash) ? item["revised_prompt"] : nil }.first
        )
      end

      private

      def normalize_images(data)
        Array(data).filter_map do |item|
          next unless item.is_a?(Hash)

          b64_json = item["b64_json"]
          mime_type = item["mime_type"] || "image/png"

          {
            "url" => item["url"],
            "b64_json" => b64_json,
            "data_url" => b64_json ? "data:#{mime_type};base64,#{b64_json}" : nil,
            "mime_type" => mime_type,
            "revised_prompt" => item["revised_prompt"],
            "raw" => item,
          }.compact
        end
      end
    end
  end
end
