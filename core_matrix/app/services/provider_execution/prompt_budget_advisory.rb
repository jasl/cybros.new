module ProviderExecution
  class PromptBudgetAdvisory
    def self.call(...)
      new(...).call
    end

    def initialize(provider_handle:, model_ref:, api_model:, tokenizer_hint:, context_window_tokens:, max_output_tokens:, context_soft_limit_ratio:, input: nil)
      @provider_handle = provider_handle
      @model_ref = model_ref
      @api_model = api_model
      @tokenizer_hint = tokenizer_hint
      @context_window_tokens = context_window_tokens.to_i
      @max_output_tokens = max_output_tokens.to_i
      @context_soft_limit_ratio = context_soft_limit_ratio.to_f
      @input = input
    end

    def call
      estimate = input_estimate

      {
        "provider_handle" => @provider_handle,
        "model_ref" => @model_ref,
        "api_model" => @api_model,
        "tokenizer_hint" => @tokenizer_hint,
        "estimated_tokens" => estimate&.fetch("estimated_tokens"),
        "remaining_tokens" => estimate.present? ? [hard_input_token_limit - estimate.fetch("estimated_tokens"), 0].max : nil,
        "hard_context_limit" => @context_window_tokens,
        "hard_input_token_limit" => hard_input_token_limit,
        "recommended_input_tokens" => recommended_input_tokens,
        "recommended_compaction_threshold" => recommended_compaction_threshold,
        "soft_threshold_tokens" => soft_threshold_tokens,
        "reserved_tokens" => reserved_tokens,
        "reserved_output_tokens" => @max_output_tokens,
        "decision_hint" => decision_hint_for(estimate),
        "diagnostics" => estimate.present? ? {
          "estimator_strategy" => estimate.fetch("strategy"),
          "estimator_details" => estimate.fetch("diagnostics"),
        } : {},
      }.compact
    end

    private

    def input_estimate
      return if @input.nil?

      @input_estimate ||= ProviderExecution::TokenEstimator.call(
        input: @input,
        tokenizer_hint: @tokenizer_hint
      )
    end

    def hard_input_token_limit
      [@context_window_tokens - @max_output_tokens, 0].max
    end

    def soft_threshold_tokens
      (@context_window_tokens * @context_soft_limit_ratio).floor
    end

    def recommended_input_tokens
      [soft_threshold_tokens, hard_input_token_limit].min
    end

    def recommended_compaction_threshold
      recommended_input_tokens
    end

    def reserved_tokens
      [@context_window_tokens - recommended_input_tokens, 0].max
    end

    def decision_hint_for(estimate)
      return "allow" if estimate.blank?

      estimated_tokens = estimate.fetch("estimated_tokens")
      return "allow" if estimated_tokens <= recommended_input_tokens
      return "consult" if estimated_tokens <= hard_input_token_limit

      "compact_required"
    end
  end
end
