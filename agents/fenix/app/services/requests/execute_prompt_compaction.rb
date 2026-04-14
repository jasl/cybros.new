module Requests
  class ExecutePromptCompaction
    def self.call(...)
      new(...).call
    end

    def initialize(payload:)
      @payload = payload.deep_stringify_keys
    end

    def call
      strategy_result = PromptCompaction::BaselineStrategy.call(
        messages: prompt_compaction.fetch("candidate_messages", []),
        hard_input_token_limit: hard_input_token_limit,
        recommended_compaction_threshold: recommended_compaction_threshold,
        selected_input_message_id: prompt_compaction["selected_input_message_id"]
      )

      {
        "status" => "ok",
        "artifact" => strategy_result.merge(
          "artifact_kind" => "prompt_compaction_context",
          "source" => "runtime"
        ),
      }
    end

    private

    def provider_context
      @payload.fetch("provider_context", {}).deep_stringify_keys
    end

    def prompt_compaction
      @payload.fetch("prompt_compaction", {}).deep_stringify_keys
    end

    def hard_input_token_limit
      provider_context.dig("budget_hints", "hard_limits", "hard_input_token_limit") || 0
    end

    def recommended_compaction_threshold
      provider_context.dig("budget_hints", "advisory_hints", "recommended_compaction_threshold") || 0
    end
  end
end
