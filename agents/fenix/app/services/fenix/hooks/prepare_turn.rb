module Fenix
  module Hooks
    class PrepareTurn
      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      def call
        messages = Array(@context.fetch("context_messages")).map(&:deep_stringify_keys)
        likely_model = @context.dig("model_context", "likely_model") || @context.dig("provider_execution", "model_ref")

        {
          "messages" => messages,
          "likely_model" => likely_model,
          "estimated_message_count" => EstimateMessages.call(messages: messages),
          "estimated_token_count" => EstimateTokens.call(messages: messages),
          "trace" => {
            "hook" => "prepare_turn",
            "message_count" => EstimateMessages.call(messages: messages),
            "estimated_token_count" => EstimateTokens.call(messages: messages),
            "likely_model" => likely_model,
          },
        }
      end
    end
  end
end
