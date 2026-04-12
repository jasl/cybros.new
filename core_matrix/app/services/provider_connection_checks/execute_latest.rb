module ProviderConnectionChecks
  class ExecuteLatest
    TEST_PROMPT = "Reply with the single word pong.".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(connection_check:)
      @connection_check = connection_check
    end

    def call
      @connection_check.with_lock do
        return @connection_check unless @connection_check.queued?

        @connection_check.update!(
          lifecycle_state: "running",
          started_at: Time.current
        )
      end

      result = ProviderGateway::DispatchText.call(
        installation: @connection_check.installation,
        selector: @connection_check.request_payload.fetch("selector"),
        messages: [
          { "role" => "user", "content" => TEST_PROMPT },
        ],
        max_output_tokens: 16,
        purpose: "provider_connection_test"
      )

      @connection_check.update!(
        lifecycle_state: "succeeded",
        finished_at: Time.current,
        result_payload: {
          "provider_request_id" => result.provider_request_id,
          "duration_ms" => result.duration_ms,
          "content_preview" => result.content.to_s.truncate(120),
        },
        failure_payload: {}
      )
    rescue ProviderGateway::DispatchText::UnavailableSelector => error
      record_failure!(
        "reason_key" => error.reason_key,
        "selector" => error.selector,
        "message" => error.message,
      )
    rescue ProviderGateway::DispatchText::RequestFailed => error
      record_failure!(
        "error_class" => error.error.class.name,
        "message" => error.error.message,
        "provider_request_id" => error.provider_request_id,
        "duration_ms" => error.duration_ms,
      )
    rescue StandardError => error
      record_failure!(
        "error_class" => error.class.name,
        "message" => error.message,
      )
      raise
    end

    private

    def record_failure!(payload)
      @connection_check.update!(
        lifecycle_state: "failed",
        finished_at: Time.current,
        result_payload: {},
        failure_payload: payload
      )
    end
  end
end
