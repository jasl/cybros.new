module ProviderExecution
  class FailureClassification
    Result = Struct.new(
      :failure_category,
      :failure_kind,
      :wait_reason_kind,
      :retry_strategy,
      :max_auto_retries,
      :next_retry_at,
      :terminal,
      :last_error_summary,
      keyword_init: true
    ) do
      def terminal?
        terminal
      end
    end

    DEFAULT_AUTO_RETRY_LIMIT = 2
    CONTRACT_AUTO_RETRY_LIMIT = 1

    def self.call(...)
      new(...).call
    end

    def initialize(error:)
      @error = error
    end

    def call
      return admission_refused_result if @error.is_a?(ProviderExecution::ProviderRequestGovernor::AdmissionRefused)
      return prompt_size_result(@error.failure_kind) if prompt_size_failure?(@error)
      return http_error_result if @error.is_a?(SimpleInference::HTTPError)
      return transport_error_result("provider_unreachable") if @error.is_a?(SimpleInference::TimeoutError) || @error.is_a?(SimpleInference::ConnectionError)
      return contract_error_result("invalid_provider_response_contract") if @error.is_a?(SimpleInference::DecodeError)
      return protocol_error_result if @error.is_a?(ProviderExecution::AgentRequestExchange::ProtocolError)
      return transport_error_result("agent_transport_failed") if @error.is_a?(ProviderExecution::AgentRequestExchange::TimeoutError)
      return request_failed_result if @error.is_a?(ProviderExecution::AgentRequestExchange::RequestFailed)
      return contract_error_result("unknown_tool_reference") if @error.is_a?(ActiveRecord::RecordNotFound)
      return contract_error_result("invalid_tool_arguments") if @error.is_a?(ActiveRecord::RecordInvalid)
      return contract_error_result("invalid_tool_call_contract") if @error.is_a?(KeyError)
      return contract_error_result("provider_round_limit_exceeded") if @error.is_a?(ProviderExecution::ExecuteRoundLoop::RoundLimitExceeded)

      implementation_error_result("internal_unexpected_error")
    end

    private

    def admission_refused_result
      external_result(
        failure_kind: "provider_rate_limited",
        retry_strategy: "automatic",
        next_retry_at: @error.retry_at
      )
    end

    def http_error_result
      status = @error.status.to_i
      body_text = [@error.message, @error.raw_body, @error.body].compact.join(" ").downcase

      return prompt_size_result("context_window_exceeded_after_compaction") if prompt_overflow_http_error?(status, body_text)
      return external_result(failure_kind: "provider_credits_exhausted", retry_strategy: "manual") if credits_exhausted?(status, body_text)
      return external_result(failure_kind: "provider_auth_expired", retry_strategy: "manual") if status.in?([401, 403])
      return external_result(failure_kind: "provider_rate_limited", retry_strategy: "automatic", next_retry_at: retry_at_from_headers) if status == 429
      return external_result(failure_kind: "provider_overloaded", retry_strategy: "automatic") if status >= 500

      implementation_error_result("internal_unexpected_error")
    end

    def request_failed_result
      payload = @error.error_payload.deep_stringify_keys
      code = payload["code"].to_s

      return contract_error_result("invalid_agent_response_contract") if code.start_with?("invalid_")
      return transport_error_result("agent_transport_failed") if @error.retryable

      external_result(failure_kind: "agent_transport_failed", retry_strategy: "manual")
    end

    def protocol_error_result
      contract_error_result("invalid_agent_response_contract")
    end

    def transport_error_result(failure_kind)
      external_result(failure_kind:, retry_strategy: "automatic")
    end

    def prompt_size_result(failure_kind)
      Result.new(
        failure_category: "contract_error",
        failure_kind: failure_kind,
        wait_reason_kind: "retryable_failure",
        retry_strategy: "manual",
        max_auto_retries: 0,
        next_retry_at: nil,
        terminal: false,
        last_error_summary: @error.message
      )
    end

    def contract_error_result(failure_kind)
      Result.new(
        failure_category: "contract_error",
        failure_kind: failure_kind,
        wait_reason_kind: "retryable_failure",
        retry_strategy: "automatic",
        max_auto_retries: CONTRACT_AUTO_RETRY_LIMIT,
        next_retry_at: nil,
        terminal: false,
        last_error_summary: @error.message
      )
    end

    def external_result(failure_kind:, retry_strategy:, next_retry_at: nil)
      Result.new(
        failure_category: "external_dependency_blocked",
        failure_kind: failure_kind,
        wait_reason_kind: "external_dependency_blocked",
        retry_strategy: retry_strategy,
        max_auto_retries: retry_strategy == "automatic" ? DEFAULT_AUTO_RETRY_LIMIT : 0,
        next_retry_at: next_retry_at,
        terminal: false,
        last_error_summary: @error.message
      )
    end

    def implementation_error_result(failure_kind)
      Result.new(
        failure_category: "implementation_error",
        failure_kind: failure_kind,
        wait_reason_kind: nil,
        retry_strategy: nil,
        max_auto_retries: 0,
        next_retry_at: nil,
        terminal: true,
        last_error_summary: @error.message
      )
    end

    def credits_exhausted?(status, body_text)
      return true if status == 402

      body_text.include?("more credits") ||
        body_text.include?("insufficient credits") ||
        body_text.include?("credit balance") ||
        body_text.include?("quota exceeded")
    end

    def prompt_size_failure?(error)
      error.respond_to?(:failure_kind) &&
        error.failure_kind.to_s.in?(%w[prompt_too_large_for_retry context_window_exceeded_after_compaction])
    end

    def prompt_overflow_http_error?(status, body_text)
      ProviderExecution::PromptOverflowDetection.matches?(status: status, body_text: body_text)
    end

    def retry_at_from_headers
      retry_after = @error.headers["retry-after"] || @error.headers["Retry-After"]
      return if retry_after.blank?

      integer_value = Integer(retry_after, exception: false)
      return Time.current + [integer_value, 1].max if integer_value.present?

      Time.httpdate(retry_after.to_s)
    rescue ArgumentError
      nil
    end
  end
end
