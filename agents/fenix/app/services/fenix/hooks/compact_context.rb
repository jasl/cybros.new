module Fenix
  module Hooks
    class CompactContext
      def self.call(...)
        new(...).call
      end

      def initialize(messages:, budget_hints:, likely_model:)
        @messages = Array(messages).map(&:deep_stringify_keys)
        @budget_hints = budget_hints.deep_stringify_keys
        @likely_model = likely_model
      end

      def call
        before_message_count = EstimateMessages.call(messages: @messages)
        estimated_tokens = EstimateTokens.call(messages: @messages)
        threshold = @budget_hints.fetch("advisory_compaction_threshold_tokens", 0).to_i

        compacted_messages =
          if threshold.positive? && estimated_tokens > threshold && @messages.size > 2
            preserved_head = @messages.first["role"] == "system" ? [@messages.first] : []
            preserved_tail = @messages.last(2)
            preserved_head + [
              {
                "role" => "system",
                "content" => "Earlier context compacted for #{@likely_model || "unknown-model"}.",
              },
            ] + preserved_tail
          else
            @messages
          end

        {
          "messages" => compacted_messages,
          "trace" => {
            "hook" => "compact_context",
            "compacted" => compacted_messages != @messages,
            "likely_model" => @likely_model,
            "before_message_count" => before_message_count,
            "after_message_count" => EstimateMessages.call(messages: compacted_messages),
          },
        }
      end
    end
  end
end
