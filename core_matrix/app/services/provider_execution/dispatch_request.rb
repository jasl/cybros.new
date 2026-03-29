require "securerandom"

module ProviderExecution
  class DispatchRequest
    class RequestFailed < StandardError
      attr_reader :error, :duration_ms, :provider_request_id

      def initialize(error:, duration_ms:, provider_request_id:)
        super(error.message)
        @error = error
        @duration_ms = duration_ms
        @provider_request_id = provider_request_id
      end
    end

    Result = Struct.new(
      :provider_result,
      :provider_request_id,
      :content,
      :usage,
      :duration_ms,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:, request_context:, messages:, adapter: nil, catalog: nil, effective_catalog: nil, provider_request_id: SecureRandom.uuid, on_delta: nil)
      @workflow_run = workflow_run
      @request_context = ProviderRequestContext.wrap(request_context)
      @messages = normalize_messages(messages)
      @adapter = adapter
      @effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: workflow_run.installation, catalog: catalog)
      @effective_catalog = effective_catalog if effective_catalog.present?
      @provider_request_id = provider_request_id
      @on_delta = on_delta
    end

    def call
      started_monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      provider_result = if @on_delta.present?
        build_client.chat(
          model: @request_context.api_model,
          messages: @messages,
          max_tokens: @request_context.hard_limits["max_output_tokens"],
          stream: true,
          include_usage: true,
          **@request_context.execution_settings.symbolize_keys
        ) do |delta|
          @on_delta.call(delta)
        end
      else
        build_client.chat(
          model: @request_context.api_model,
          messages: @messages,
          max_tokens: @request_context.hard_limits["max_output_tokens"],
          **@request_context.execution_settings.symbolize_keys
        )
      end

      Result.new(
        provider_result: provider_result,
        provider_request_id: provider_request_id_for(provider_result),
        content: provider_result.content.to_s,
        usage: normalize_usage(provider_result.usage),
        duration_ms: elapsed_ms_since(started_monotonic)
      )
    rescue SimpleInference::Error => error
      raise RequestFailed.new(
        error: error,
        duration_ms: elapsed_ms_since(started_monotonic),
        provider_request_id: @provider_request_id
      )
    end

    private

    def build_client
      provider_definition = @effective_catalog.provider(@request_context.provider_handle)

      SimpleInference::Client.new(
        base_url: provider_definition.fetch(:base_url),
        api_key: credential_secret_for(provider_definition),
        headers: provider_definition.fetch(:headers, {}),
        adapter: @adapter || SimpleInference::HTTPAdapters::HTTPX.new
      )
    end

    def credential_secret_for(provider_definition)
      return nil unless provider_definition.fetch(:requires_credential)

      ProviderCredential.find_by!(
        installation: @workflow_run.installation,
        provider_handle: @request_context.provider_handle,
        credential_kind: provider_definition.fetch(:credential_kind)
      ).secret
    end

    def normalize_messages(messages)
      Array(messages).filter_map do |message|
        candidate = message.is_a?(Hash) ? message : nil
        next if candidate.blank?

        {
          "role" => candidate["role"] || candidate[:role],
          "content" => candidate["content"] || candidate[:content],
        }.compact
      end
    end

    def normalize_usage(usage)
      payload = usage.is_a?(Hash) ? usage : {}

      {
        "input_tokens" => payload[:prompt_tokens] || payload["prompt_tokens"] || payload[:input_tokens] || payload["input_tokens"],
        "output_tokens" => payload[:completion_tokens] || payload["completion_tokens"] || payload[:output_tokens] || payload["output_tokens"],
        "total_tokens" => payload[:total_tokens] || payload["total_tokens"],
      }.compact
    end

    def provider_request_id_for(provider_result)
      provider_result.response.headers["x-request-id"] ||
        provider_result.response.body&.fetch("id", nil) ||
        @provider_request_id
    end

    def elapsed_ms_since(started_monotonic)
      return 0 if started_monotonic.nil?

      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_monotonic) * 1000).round
    end
  end
end
