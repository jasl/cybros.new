# frozen_string_literal: true

require_relative "openai_compatible"

module SimpleInference
  module Protocols
    class OpenAICompatibleResponses < OpenAICompatible
      def create(model:, input:, **options)
        result = chat(model: model, messages: coerce_messages(input, options), stream: false, **chat_options(options))
        SimpleInference::Responses::Result.from_openai_chat(result)
      end

      def stream(model:, input:, **options)
        SimpleInference::Responses::Stream.new do |&emit|
          raw_result =
            chat(model: model, messages: coerce_messages(input, options), stream: true, **chat_options(options)) do |delta|
              emit.call(SimpleInference::Responses::Events::TextDelta.new(delta: delta))
            end

          result = SimpleInference::Responses::Result.from_openai_chat(raw_result)
          emit.call(SimpleInference::Responses::Events::Completed.new(result: result, raw: result.provider_response&.body))
          result
        end
      end

      private

      def coerce_messages(input, options)
        return input if input.is_a?(Array)

        messages = []
        instructions = options[:instructions] || options["instructions"]
        messages << { role: "system", content: instructions.to_s } unless instructions.to_s.strip.empty?
        messages << { role: "user", content: input }
        messages
      end

      def chat_options(options)
        normalized = options.each_with_object({}) do |(key, value), out|
          next if key.to_s == "instructions"

          normalized_key = key.to_s == "max_output_tokens" ? :max_tokens : key
          out[normalized_key] = value
        end

        normalized
      end
    end
  end
end
