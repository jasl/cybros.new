module Fenix
  module Hooks
    class CompactContext
      ToolNotAllowedError = Class.new(StandardError)

      def self.call(...)
        new(...).call
      end

      def initialize(messages:, budget_hints:, likely_model: nil)
        @messages = Array(messages).map(&:deep_stringify_keys)
        @budget_hints = budget_hints.deep_stringify_keys
        @likely_model = likely_model
      end

      def call
        threshold =
          @budget_hints.dig("advisory_hints", "recommended_compaction_threshold") ||
          @budget_hints["advisory_compaction_threshold_tokens"] ||
          0

        compacted_messages =
          if threshold.to_i.positive? && estimated_tokens > threshold.to_i && @messages.size > 2
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
          "compacted" => compacted_messages != @messages,
          "estimated_tokens" => estimated_tokens,
        }
      end

      private

      def estimated_tokens
        @messages.sum do |message|
          [(message["content"].to_s.length / 4.0).ceil, 1].max
        end
      end
    end
  end
end
