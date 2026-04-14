module ProviderExecution
  class PromptBudgetGuard
    RESERVE_FLOOR_TOKENS = 0
    HEURISTIC_TOKEN_SAFETY_BUFFER = 0
    MESSAGE_OVERHEAD_TOKENS = 8
    MAX_COMPACTION_ATTEMPTS = 1
    MAX_OVERFLOW_RECOVERY_ATTEMPTS = 1

    def self.call(...)
      new(...).call
    end

    def initialize(messages:, request_context:, policy:, selected_input_message: nil)
      @messages = Array(messages).map { |entry| normalize_message(entry) }.compact
      @request_context = ProviderRequestContext.wrap(request_context)
      @policy = policy.is_a?(Hash) ? policy.deep_stringify_keys : {}
      @selected_input_message = normalize_selected_input(selected_input_message)
    end

    def call
      estimate_result = estimate(@messages)
      selected_input_estimate = estimate([selected_input_payload])
      effective_estimated_tokens = effective_estimated_tokens_for(estimate_result, @messages.length)
      effective_selected_input_tokens = effective_estimated_tokens_for(selected_input_estimate, 1)

      {
        "decision" => decision_for(effective_estimated_tokens, effective_selected_input_tokens),
        "estimated_tokens" => effective_estimated_tokens,
        "estimator_strategy" => estimate_result.fetch("strategy"),
        "failure_scope" => failure_scope_for(effective_selected_input_tokens),
        "retry_mode" => retry_mode_for(effective_estimated_tokens, effective_selected_input_tokens),
        "diagnostics" => {
          "hard_input_token_limit" => hard_input_token_limit,
          "recommended_compaction_threshold" => recommended_compaction_threshold,
          "base_estimated_tokens" => estimate_result.fetch("estimated_tokens"),
          "selected_input_estimated_tokens" => effective_selected_input_tokens,
          "selected_input_message_present" => selected_input_payload.present?,
          "feature_strategy" => @policy["strategy"].presence || "runtime_first",
          "estimator_details" => estimate_result.fetch("diagnostics"),
          "message_overhead_tokens" => message_overhead(@messages.length),
        },
      }
    end

    private

    def normalize_message(message)
      return unless message.is_a?(Hash)

      message.deep_stringify_keys
    end

    def normalize_selected_input(selected_input_message)
      return if selected_input_message.blank?
      return normalize_message(selected_input_message) if selected_input_message.is_a?(Hash)

      { "role" => "user", "content" => selected_input_message.to_s }
    end

    def estimate(messages)
      ProviderExecution::TokenEstimator.call(
        input: Array(messages),
        tokenizer_hint: @request_context.tokenizer_hint
      )
    end

    def selected_input_payload
      @selected_input_payload ||= @selected_input_message || @messages.reverse.find do |message|
        message["role"].to_s == "user" && message["content"].present?
      end || @messages.last || { "role" => "user", "content" => "" }
    end

    def hard_input_token_limit
      @hard_input_token_limit ||= @request_context.hard_limits.fetch("hard_input_token_limit").to_i
    end

    def recommended_compaction_threshold
      raw = @request_context.advisory_hints["recommended_compaction_threshold"]
      value = raw.present? ? raw.to_i : hard_input_token_limit
      [[value, hard_input_token_limit].min, RESERVE_FLOOR_TOKENS].max
    end

    def decision_for(effective_estimated_tokens, effective_selected_input_tokens)
      return "reject" if effective_selected_input_tokens > hard_input_token_limit

      return "allow" if effective_estimated_tokens <= recommended_compaction_threshold
      return "consult" if effective_estimated_tokens <= hard_input_token_limit

      "compact_required"
    end

    def failure_scope_for(effective_selected_input_tokens)
      return "current_input" if effective_selected_input_tokens > hard_input_token_limit

      nil
    end

    def retry_mode_for(effective_estimated_tokens, effective_selected_input_tokens)
      return "edit_current_input" if effective_selected_input_tokens > hard_input_token_limit
      return "workflow_compaction" if effective_estimated_tokens > hard_input_token_limit
      return "runtime_consultation" if effective_estimated_tokens > recommended_compaction_threshold

      "none"
    end

    def effective_estimated_tokens_for(estimate_result, message_count)
      estimate_result.fetch("estimated_tokens") + message_overhead(message_count)
    end

    def message_overhead(message_count)
      [message_count.to_i, 0].max * MESSAGE_OVERHEAD_TOKENS
    end
  end
end
