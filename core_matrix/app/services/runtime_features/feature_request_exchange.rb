require "securerandom"

module RuntimeFeatures
  class FeatureRequestExchange
    DEFAULT_TIMEOUT = 30.seconds
    DEFAULT_POLL_INTERVAL = 0.05
    MAX_POLL_INTERVAL = 1.0

    class ExchangeError < StandardError
      attr_reader :code, :details, :retryable

      def initialize(code:, message:, details: {}, retryable: false)
        @code = code
        @details = details
        @retryable = retryable
        super(message)
      end
    end

    class TimeoutError < ExchangeError; end

    class RequestFailed < ExchangeError
      attr_reader :error_payload

      def initialize(error_payload:, details: {}, retryable: false)
        @error_payload = error_payload.deep_stringify_keys
        super(
          code: @error_payload.fetch("code", "feature_request_failed"),
          message: @error_payload.fetch("message", "feature request failed"),
          details: details,
          retryable: retryable
        )
      end
    end

    TERMINAL_METHODS = %w[agent_completed agent_failed].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, timeout: DEFAULT_TIMEOUT, poll_interval: DEFAULT_POLL_INTERVAL, sleeper: nil)
      @agent_definition_version = agent_definition_version
      @timeout = timeout
      @poll_interval = poll_interval
      @sleeper = sleeper || ->(duration) { sleep(duration) }
    end

    def execute_feature(feature_key:, request_payload:, conversation_id: nil, turn_id: nil)
      mailbox_item = AgentControl::CreateAgentRequest.call(
        agent_definition_version: @agent_definition_version,
        request_kind: "execute_feature",
        payload: mailbox_payload(
          feature_key: feature_key,
          request_payload: request_payload,
          conversation_id: conversation_id,
          turn_id: turn_id
        ),
        logical_work_id: "execute-feature:#{feature_key}:#{SecureRandom.uuid}",
        attempt_no: 1,
        dispatch_deadline_at: Time.current + @timeout,
        execution_hard_deadline_at: Time.current + @timeout,
        lease_timeout_seconds: [@timeout.to_f.ceil + 10, 1].max
      )

      receipt = wait_for_terminal_receipt!(mailbox_item, timeout: @timeout)
      payload = receipt.payload.deep_stringify_keys

      return payload.fetch("response_payload") if payload.fetch("method_id") == "agent_completed"

      raise RequestFailed.new(
        error_payload: payload.fetch("error_payload"),
        details: { "mailbox_item_id" => mailbox_item.public_id, "feature_key" => feature_key }
      )
    end

    private

    def mailbox_payload(feature_key:, request_payload:, conversation_id:, turn_id:)
      {
        "protocol_version" => "agent-runtime/2026-04-01",
        "request_kind" => "execute_feature",
        "task" => {
          "kind" => "feature",
          "conversation_id" => conversation_id,
          "turn_id" => turn_id,
        }.compact,
        "feature" => {
          "feature_key" => feature_key,
          "input" => request_payload.deep_stringify_keys,
        },
      }
    end

    def wait_for_terminal_receipt!(mailbox_item, timeout:)
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout.to_f
      poll_attempt = 0

      loop do
        receipt = AgentControlReportReceipt.uncached do
          AgentControlReportReceipt.find_by(mailbox_item_id: mailbox_item.id, method_id: TERMINAL_METHODS)
        end
        return receipt if receipt.present?

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
          raise TimeoutError.new(
            code: "mailbox_timeout",
            message: "timed out waiting for feature response",
            details: { "mailbox_item_id" => mailbox_item.public_id },
            retryable: true
          )
        end

        poll_attempt += 1
        @sleeper.call(poll_interval_for_attempt(poll_attempt))
      end
    end

    def poll_interval_for_attempt(poll_attempt)
      exponent = [poll_attempt - 1, 4].min
      [@poll_interval * (2**exponent), MAX_POLL_INTERVAL].min
    end
  end
end
