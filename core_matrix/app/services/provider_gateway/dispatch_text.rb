require "securerandom"

module ProviderGateway
  class DispatchText
    MAX_TRANSIENT_REQUEST_ATTEMPTS = 2
    RETRYABLE_PROVIDER_ERRORS = [
      SimpleInference::TimeoutError,
      SimpleInference::ConnectionError,
    ].freeze

    class RequestFailed < StandardError
      attr_reader :error, :duration_ms, :provider_request_id

      def initialize(error:, duration_ms:, provider_request_id:)
        super(error.message)
        @error = error
        @duration_ms = duration_ms
        @provider_request_id = provider_request_id
      end
    end

    class UnavailableSelector < StandardError
      attr_reader :selector, :reason_key

      def initialize(selector:, reason_key:)
        super("no candidate available for #{selector}: #{reason_key}")
        @selector = selector
        @reason_key = reason_key
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

    def initialize(
      installation:,
      selector:,
      messages:,
      max_output_tokens:,
      request_overrides: {},
      purpose: nil,
      adapter: nil,
      catalog: nil,
      effective_catalog: nil,
      governor: ProviderExecution::ProviderRequestGovernor,
      lease_renew_interval_seconds: nil,
      audit_context: nil
    )
      @installation = installation
      @selector = selector.to_s
      @messages = normalize_messages(messages)
      @max_output_tokens = max_output_tokens.to_i
      @request_overrides = request_overrides || {}
      @purpose = purpose.to_s.presence
      @adapter = adapter
      @provider_request_id = SecureRandom.uuid
      @effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation, catalog: catalog)
      @effective_catalog = effective_catalog if effective_catalog.present?
      @governor = governor
      @lease_renew_interval_seconds = lease_renew_interval_seconds || @governor::DEFAULT_LEASE_RENEW_INTERVAL_SECONDS
      @audit_context = audit_context
    end

    def call
      started_monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      provider_result = ProviderExecution::WithProviderRequestLease.call(
        installation: @installation,
        request_context: request_context,
        effective_catalog: @effective_catalog,
        governor: @governor,
        lease_renew_interval_seconds: @lease_renew_interval_seconds
      ) do
        dispatch_with_transient_retry
      end

      Result.new(
        provider_result: provider_result,
        provider_request_id: provider_request_id_for(provider_result),
        content: provider_result_content(provider_result),
        usage: normalize_usage(provider_result.usage),
        duration_ms: elapsed_ms_since(started_monotonic)
      )
    rescue ProviderExecution::ProviderRequestGovernor::AdmissionRefused
      raise
    rescue SimpleInference::Error => error
      raise RequestFailed.new(
        error: error,
        duration_ms: elapsed_ms_since(started_monotonic),
        provider_request_id: @provider_request_id
      )
    end

    private

    def request_context
      @request_context ||= begin
        resolution = resolve_selector!
        provider_definition = @effective_catalog.provider(resolution.provider_handle)
        model_definition = @effective_catalog.model(resolution.provider_handle, resolution.model_ref)
        execution_settings = ProviderRequestSettingsSchema
          .for(provider_definition.fetch(:wire_api))
          .merge_execution_settings(
            request_defaults: model_definition.fetch(:request_defaults, {}),
            runtime_overrides: @request_overrides
          )

        ProviderRequestContext.new(
          "provider_handle" => resolution.provider_handle,
          "model_ref" => resolution.model_ref,
          "api_model" => model_definition.fetch(:api_model),
          "wire_api" => provider_definition.fetch(:wire_api),
          "transport" => provider_definition.fetch(:transport),
          "tokenizer_hint" => model_definition.fetch(:tokenizer_hint),
          "execution_settings" => execution_settings,
          "hard_limits" => {
            "max_output_tokens" => [@max_output_tokens, model_definition.fetch(:max_output_tokens)].min,
          },
          "advisory_hints" => {
            "recommended_compaction_threshold" => (model_definition.fetch(:context_window_tokens) * model_definition.fetch(:context_soft_limit_ratio)).floor,
          },
          "provider_metadata" => provider_definition.fetch(:metadata, {}).deep_stringify_keys,
          "model_metadata" => model_definition.fetch(:metadata, {}).deep_stringify_keys,
        )
      end
    end

    def resolve_selector!
      result = @effective_catalog.resolve_selector(selector: @selector)
      return result if result.usable?

      raise UnavailableSelector.new(selector: result.normalized_selector, reason_key: result.reason_key)
    end

    def build_client
      provider_definition = @effective_catalog.provider(request_context.provider_handle)
      adapter = @adapter || ProviderExecution::BuildHttpAdapter.call(provider_definition: provider_definition)

      case request_context.wire_api
      when "responses"
        SimpleInference::Protocols::OpenAIResponses.new(
          base_url: provider_definition.fetch(:base_url),
          api_key: credential_secret_for(provider_definition),
          headers: provider_definition.fetch(:headers, {}),
          responses_path: provider_definition.fetch(:responses_path),
          adapter: adapter
        )
      else
        SimpleInference::Client.new(
          base_url: provider_definition.fetch(:base_url),
          api_key: credential_secret_for(provider_definition),
          headers: provider_definition.fetch(:headers, {}),
          adapter: adapter
        )
      end
    end

    def credential_secret_for(provider_definition)
      return nil unless provider_definition.fetch(:requires_credential)

      ProviderCredential.find_by!(
        installation: @installation,
        provider_handle: request_context.provider_handle,
        credential_kind: provider_definition.fetch(:credential_kind)
      ).secret
    end

    def dispatch_with_transient_retry
      attempt = 0

      begin
        attempt += 1
        @received_delta = false

        case request_context.wire_api
        when "responses"
          dispatch_responses_request
        else
          dispatch_chat_request
        end
      rescue *RETRYABLE_PROVIDER_ERRORS => error
        raise if @received_delta
        raise if attempt >= MAX_TRANSIENT_REQUEST_ATTEMPTS

        retry
      end
    end

    def dispatch_chat_request
      request = {
        model: request_context.api_model,
        messages: @messages,
        max_tokens: request_context.hard_limits["max_output_tokens"],
        **request_context.execution_settings.symbolize_keys,
      }

      build_client.chat(**request)
    end

    def dispatch_responses_request
      request = {
        model: request_context.api_model,
        input: @messages,
        max_output_tokens: request_context.hard_limits["max_output_tokens"],
        **request_context.execution_settings.symbolize_keys,
      }

      build_client.responses(**request)
    end

    def normalize_messages(messages)
      Array(messages).filter_map do |message|
        candidate = message.is_a?(Hash) ? message : nil
        next if candidate.blank?

        normalized = candidate.deep_stringify_keys.slice(
          "role",
          "content",
          "tool_call_id",
          "call_id",
          "name",
          "tool_calls",
          "type",
          "output",
          "arguments",
          "id"
        )
        normalized["role"] = normalize_provider_role(normalized["role"])
        tool_call_id = candidate["tool_call_id"] || candidate[:tool_call_id]

        normalized["tool_call_id"] = tool_call_id if tool_call_id.present?
        normalized["call_id"] = candidate["call_id"] || candidate[:call_id] || tool_call_id if tool_call_id.present? || candidate["call_id"].present? || candidate[:call_id].present?
        normalized["name"] = candidate["name"] || candidate[:name] if (candidate["name"] || candidate[:name]).present?
        normalized.compact
      end
    end

    def normalize_provider_role(role)
      case role
      when "agent"
        "assistant"
      else
        role
      end
    end

    def normalize_usage(usage)
      ProviderUsage::NormalizeMetrics.call(usage:, request_context:)
    end

    def provider_result_content(provider_result)
      if provider_result.respond_to?(:output_text)
        provider_result.output_text.to_s
      else
        provider_result.content.to_s
      end
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
