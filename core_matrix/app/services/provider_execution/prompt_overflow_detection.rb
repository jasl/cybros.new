module ProviderExecution
  module PromptOverflowDetection
    REQUESTED_TOKENS_PATTERN = /requested\s+\d+\s+tokens/.freeze

    def self.matches?(status:, body_text:)
      normalized_text = body_text.to_s.downcase

      status.to_i == 413 ||
        normalized_text.include?("context_length_exceeded") ||
        normalized_text.include?("maximum context length") ||
        normalized_text.include?("context window") ||
        normalized_text.include?("too many tokens") ||
        normalized_text.include?("prompt is too long") ||
        normalized_text.include?("reduce the length") ||
        normalized_text.match?(REQUESTED_TOKENS_PATTERN)
    end
  end
end
