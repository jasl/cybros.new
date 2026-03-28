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
        likely_model =
          @context.dig("model_context", "likely_model") ||
          @context.dig("model_context", "model_ref") ||
          @context.dig("model_context", "api_model") ||
          @context.dig("provider_execution", "model_ref")
        agent_context = @context.fetch("agent_context", {}).deep_stringify_keys

        {
          "messages" => messages,
          "likely_model" => likely_model,
          "agent_context" => agent_context,
          "estimated_message_count" => EstimateMessages.call(messages: messages),
          "estimated_token_count" => EstimateTokens.call(messages: messages),
          "trace" => {
            "hook" => "prepare_turn",
            "message_count" => EstimateMessages.call(messages: messages),
            "estimated_token_count" => EstimateTokens.call(messages: messages),
            "likely_model" => likely_model,
            "profile" => agent_context["profile"],
            "is_subagent" => agent_context["is_subagent"] == true,
            "allowed_tool_names" => Array(agent_context["allowed_tool_names"]),
          },
        }
      end
    end
  end
end
