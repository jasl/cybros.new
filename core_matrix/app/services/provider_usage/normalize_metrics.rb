module ProviderUsage
  class NormalizeMetrics
    def self.call(...)
      new(...).call
    end

    def initialize(usage:, request_context: nil, provider_metadata: nil, model_metadata: nil)
      @usage = usage.is_a?(Hash) ? usage.deep_stringify_keys : {}
      wrapped_request_context = request_context.present? ? ProviderRequestContext.wrap(request_context) : nil
      @provider_metadata = metadata_hash(provider_metadata || wrapped_request_context&.provider_metadata)
      @model_metadata = metadata_hash(model_metadata || wrapped_request_context&.model_metadata)
    end

    def call
      {
        "input_tokens" => input_tokens,
        "output_tokens" => output_tokens,
        "total_tokens" => total_tokens,
        "prompt_cache_status" => prompt_cache_status,
        "cached_input_tokens" => cached_input_tokens,
      }.compact
    end

    private

    def input_tokens
      first_present_value("prompt_tokens", "input_tokens")
    end

    def output_tokens
      first_present_value("completion_tokens", "output_tokens")
    end

    def total_tokens
      @usage["total_tokens"]
    end

    def prompt_cache_status
      return "available" unless cached_input_tokens.nil?
      return "unsupported" if prompt_cache_details_unsupported?

      "unknown"
    end

    def cached_input_tokens
      @cached_input_tokens ||= begin
        value = @usage.dig("prompt_tokens_details", "cached_tokens")
        value = @usage.dig("input_tokens_details", "cached_tokens") if value.nil?
        integer_value(value)
      end
    end

    def prompt_cache_details_unsupported?
      [@provider_metadata, @model_metadata].any? do |metadata|
        metadata.dig("usage_capabilities", "prompt_cache_details") == false
      end
    end

    def first_present_value(*keys)
      keys.each do |key|
        return @usage[key] if @usage.key?(key)
      end

      nil
    end

    def integer_value(value)
      return nil if value.nil?

      Integer(value, exception: false)
    end

    def metadata_hash(value)
      value.is_a?(Hash) ? value.deep_stringify_keys : {}
    end
  end
end
