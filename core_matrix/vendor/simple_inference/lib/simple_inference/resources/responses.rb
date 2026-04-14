# frozen_string_literal: true

module SimpleInference
  module Resources
    class Responses
      def initialize(client:)
        @client = client
      end

      def create(model:, input:, **options)
        input, options = @client.request_planner.prepare_responses_request(input: input, options: options, streaming: false)
        protocol = @client.request_planner.responses_protocol
        return protocol.create(model: model, input: input, **options) if protocol.respond_to?(:create)

        result = protocol.chat(model: model, messages: coerce_messages(input, options), stream: false, **chat_options(options))
        SimpleInference::Responses::Result.from_openai_chat(result)
      end

      def stream(model:, input:, **options)
        input, options = @client.request_planner.prepare_responses_request(input: input, options: options, streaming: true)
        protocol = @client.request_planner.responses_protocol
        return protocol.stream(model: model, input: input, **options) if protocol.respond_to?(:stream)

        SimpleInference::Responses::Stream.new do |&emit|
          raw_result =
            protocol.chat(model: model, messages: coerce_messages(input, options), stream: true, **chat_options(options)) do |delta|
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
        options.reject { |key, _| key.to_s == "instructions" }
      end
    end
  end
end
