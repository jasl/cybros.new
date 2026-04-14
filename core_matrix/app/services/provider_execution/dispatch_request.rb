require "securerandom"

module ProviderExecution
  class DispatchRequest
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

    def initialize(workflow_run:, request_context:, messages:, tools: nil, tool_choice: nil, adapter: nil, catalog: nil, effective_catalog: nil, provider_request_id: SecureRandom.uuid, on_delta: nil, workflow_node: nil)
      @workflow_run = workflow_run
      @request_context = ProviderRequestContext.wrap(request_context)
      @messages = normalize_messages(messages)
      @tools = Array(tools).map { |entry| normalize_tool_definition(entry.deep_stringify_keys) }
      @tool_choice = tool_choice
      @adapter = adapter
      @effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: workflow_run.installation, catalog: catalog)
      @effective_catalog = effective_catalog if effective_catalog.present?
      @provider_request_id = provider_request_id
      @on_delta = on_delta
      @workflow_node = workflow_node
    end

    def call
      started_monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      provider_result = ProviderExecution::WithProviderRequestLease.call(
        workflow_run: @workflow_run,
        request_context: @request_context,
        effective_catalog: @effective_catalog,
        workflow_node: @workflow_node
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

    def build_client
      provider_definition = @effective_catalog.provider(@request_context.provider_handle)
      adapter = @adapter || ProviderExecution::BuildHttpAdapter.call(provider_definition: provider_definition)

      SimpleInference::Client.new(
        base_url: provider_definition.fetch(:base_url),
        api_key: credential_secret_for(provider_definition),
        headers: provider_definition.fetch(:headers, {}),
        adapter: adapter,
        provider_profile: {
          adapter_key: provider_definition.fetch(:adapter_key),
          wire_api: @request_context.wire_api,
          responses_path: provider_definition.fetch(:responses_path),
        },
        model_profile: {
          api_model: @request_context.api_model,
          capabilities: @request_context.capabilities,
        }
      )
    end

    def credential_secret_for(provider_definition)
      return nil unless provider_definition.fetch(:requires_credential)

      credential = ProviderCredential.find_by!(
        installation: @workflow_run.installation,
        provider_handle: @request_context.provider_handle,
        credential_kind: provider_definition.fetch(:credential_kind)
      )
      return credential.secret unless credential.oauth_codex?

      credential = ProviderCredentials::RefreshOAuthCredential.call(
        installation: @workflow_run.installation,
        provider_handle: @request_context.provider_handle,
        credential: credential
      )
      credential.access_token
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
          "id",
          "provider_payload"
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
      ProviderUsage::NormalizeMetrics.call(usage:, request_context: @request_context)
    end

    def dispatch_generation_request
      request = {
        model: @request_context.api_model,
        input: @messages,
        max_output_tokens: @request_context.hard_limits["max_output_tokens"],
        **@request_context.execution_settings.symbolize_keys,
      }
      request[:tools] = @tools if @tools.present?
      request[:tool_choice] = @tool_choice if @tool_choice.present?

      if stream_request?
        stream = build_client.responses.stream(**request, include_usage: true)
        stream.each do |event|
          handle_delta(event.delta) if event.is_a?(SimpleInference::Responses::Events::TextDelta)
        end
        stream.get_final_result
      else
        build_client.responses.create(**request)
      end
    end

    def dispatch_with_transient_retry
      attempt = 0

      begin
        attempt += 1
        @received_delta = false
        dispatch_generation_request
      rescue *RETRYABLE_PROVIDER_ERRORS => error
        raise if @received_delta
        raise if attempt >= MAX_TRANSIENT_REQUEST_ATTEMPTS

        retry
      end
    end

    def provider_result_content(provider_result)
      provider_result.output_text.to_s
    end

    def provider_request_id_for(provider_result)
      response = provider_result.provider_response
      response&.headers&.fetch("x-request-id", nil) ||
        response&.body&.fetch("id", nil) ||
        @provider_request_id
    end

    def elapsed_ms_since(started_monotonic)
      return 0 if started_monotonic.nil?

      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_monotonic) * 1000).round
    end

    def normalize_tool_definition(entry)
      normalized_entry = entry.deep_dup

      if normalized_entry["function"].is_a?(Hash)
        normalized_entry["function"] = normalized_entry["function"].deep_dup
        normalized_entry["function"]["parameters"] = normalize_schema(normalized_entry["function"]["parameters"])
      elsif normalized_entry["parameters"].is_a?(Hash)
        normalized_entry["parameters"] = normalize_schema(normalized_entry["parameters"])
      end

      normalized_entry
    end

    def stream_request?
      @on_delta.present? && streaming_capability_enabled?
    end

    def handle_delta(delta)
      @received_delta = true
      @on_delta.call(delta)
    end

    def streaming_capability_enabled?
      @request_context.capabilities["streaming"] == true
    end

    def normalize_schema(schema)
      normalized = schema.is_a?(Hash) ? schema.deep_stringify_keys.deep_dup : {}

      if normalized["type"] == "array"
        normalized["items"] = normalize_schema(normalized["items"])
      elsif normalized["items"].is_a?(Hash)
        normalized["items"] = normalize_schema(normalized["items"])
      end

      if normalized["properties"].is_a?(Hash)
        normalized["properties"] = normalized["properties"].each_with_object({}) do |(key, value), properties|
          properties[key] = normalize_schema(value)
        end
      end

      %w[anyOf oneOf allOf].each do |keyword|
        next unless normalized[keyword].is_a?(Array)

        normalized[keyword] = normalized[keyword].map { |entry| normalize_schema(entry) }
      end

      normalized
    end
  end
end
