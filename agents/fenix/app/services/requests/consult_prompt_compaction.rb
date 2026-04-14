module Requests
  class ConsultPromptCompaction
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
        "decision" => decision_for(strategy_result),
        "selected_input_message_id" => prompt_compaction["selected_input_message_id"],
        "preservation_invariants" => strategy_result.fetch("preservation_invariants"),
        "diagnostics" => strategy_result.fetch("diagnostics").merge(
          "consultation_reason" => prompt_compaction["consultation_reason"],
          "failure_scope" => strategy_result["failure_scope"],
          "stop_reason" => strategy_result["stop_reason"]
        ).compact,
      }
    end

    private

    def decision_for(strategy_result)
      return "reject" if strategy_result["failure_scope"] == "current_input"
      return "compact" if strategy_result.fetch("compacted")
      return "compact" if prompt_compaction.dig("guard_result", "decision") == "compact_required"
      return "compact" if strategy_result.dig("before_estimate", "estimated_tokens").to_i > recommended_compaction_threshold

      "skip"
    end

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
