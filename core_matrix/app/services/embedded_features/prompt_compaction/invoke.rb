module EmbeddedFeatures
  module PromptCompaction
    class Invoke
      def self.call(...)
        new(...).call
      end

      def initialize(request_payload:)
        @request_payload = request_payload.deep_stringify_keys
      end

      def call
        ProviderExecution::PromptCompactionStrategy.call(
          messages: @request_payload.fetch("candidate_messages", []),
          hard_input_token_limit: budget_hints.fetch("hard_input_token_limit", 0),
          recommended_compaction_threshold: budget_hints.fetch("recommended_compaction_threshold", 0),
          selected_input_message_id: @request_payload["selected_input_message_id"],
          tokenizer_hint: @request_payload["tokenizer_hint"]
        ).merge(
          "artifact_kind" => "prompt_compaction_context",
          "source" => "embedded"
        )
      end

      private

      def budget_hints
        explicit = @request_payload.fetch("budget_hints", {})
        return explicit.deep_stringify_keys if explicit.is_a?(Hash) && explicit["hard_input_token_limit"].present?

        {
          "hard_input_token_limit" => explicit.dig("hard_limits", "hard_input_token_limit"),
          "recommended_compaction_threshold" => explicit.dig("advisory_hints", "recommended_compaction_threshold"),
        }.compact
      end
    end
  end
end
