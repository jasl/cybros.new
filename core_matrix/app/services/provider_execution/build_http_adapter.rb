module ProviderExecution
  class BuildHttpAdapter
    DEFAULT_ADAPTER_KEYS = %w[
      codex_subscription_responses
      local_openai_compatible_chat_completions
      mock_llm_chat_completions
      mock_llm_responses
      openai_responses
      openrouter_chat_completions
    ].freeze
    HTTPX_ADAPTER_KEYS = %w[
      httpx_chat_completions
      httpx_responses
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(provider_definition:)
      @provider_definition = provider_definition
    end

    def call
      adapter_key = @provider_definition.fetch(:adapter_key)

      case adapter_key
      when *DEFAULT_ADAPTER_KEYS
        SimpleInference::HTTPAdapters::Default.new
      when *HTTPX_ADAPTER_KEYS
        SimpleInference::HTTPAdapters::HTTPX.new
      else
        raise ArgumentError, "unsupported provider adapter key #{adapter_key.inspect}"
      end
    end
  end
end
