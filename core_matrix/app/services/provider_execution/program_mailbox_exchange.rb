require "securerandom"

module ProviderExecution
  class ProgramMailboxExchange
    DEFAULT_TIMEOUT = 30.seconds
    DEFAULT_POLL_INTERVAL = 0.05

    class ExchangeError < StandardError
      attr_reader :code, :details, :retryable

      def initialize(code:, message:, details: {}, retryable: false)
        @code = code
        @details = details
        @retryable = retryable
        super(message)
      end
    end

    class ProtocolError < ExchangeError; end
    class TimeoutError < ExchangeError; end
    class RequestFailed < ExchangeError
      attr_reader :error_payload

      def initialize(error_payload:, details: {}, retryable: false)
        @error_payload = error_payload.deep_stringify_keys
        super(
          code: @error_payload.fetch("code", "program_request_failed"),
          message: @error_payload.fetch("message", "agent program request failed"),
          details: details,
          retryable:
        )
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(agent_deployment:, timeout: DEFAULT_TIMEOUT, poll_interval: DEFAULT_POLL_INTERVAL, sleeper: nil)
      @agent_deployment = agent_deployment
      @timeout = timeout
      @poll_interval = poll_interval
      @sleeper = sleeper || ->(duration) { sleep(duration) }
    end

    def prepare_round(payload:)
      response = perform_request!(request_kind: "prepare_round", payload:, logical_work_id: "prepare-round:#{payload.fetch("workflow_node_id")}")
      validate_prepare_round_response!(response)
      response
    end

    def execute_program_tool(payload:)
      perform_request!(
        request_kind: "execute_program_tool",
        payload:,
        logical_work_id: "program-tool:#{payload.fetch("workflow_node_id")}:#{payload.fetch("tool_call_id")}",
        allow_failure_response: true
      )
    end

    private

    TERMINAL_METHODS = %w[agent_program_completed agent_program_failed].freeze

    def perform_request!(request_kind:, payload:, logical_work_id:, allow_failure_response: false)
      mailbox_item = AgentControl::CreateAgentProgramRequest.call(
        agent_deployment: @agent_deployment,
        request_kind: request_kind,
        payload: payload,
        logical_work_id: logical_work_id,
        attempt_no: 1,
        dispatch_deadline_at: Time.current + @timeout,
        lease_timeout_seconds: [@timeout.to_f.ceil, 1].max
      )
      receipt = wait_for_terminal_receipt!(mailbox_item)
      report_payload = receipt.payload.deep_stringify_keys

      return report_payload.fetch("response_payload") if report_payload.fetch("method_id") == "agent_program_completed"
      return { "status" => "failed", "error" => report_payload.fetch("error_payload") } if allow_failure_response

      raise RequestFailed.new(
        error_payload: report_payload.fetch("error_payload"),
        details: { "mailbox_item_id" => mailbox_item.public_id, "request_kind" => request_kind }
      )
    end

    def wait_for_terminal_receipt!(mailbox_item)
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout.to_f

      loop do
        receipt = AgentControlReportReceipt.find_by(mailbox_item: mailbox_item, method_id: TERMINAL_METHODS)
        return receipt if receipt.present?

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
          raise TimeoutError.new(
            code: "mailbox_timeout",
            message: "timed out waiting for agent program report",
            details: { "mailbox_item_id" => mailbox_item.public_id },
            retryable: true
          )
        end

        @sleeper.call(@poll_interval)
      end
    end

    def validate_prepare_round_response!(response)
      raise ProtocolError.new(code: "invalid_prepare_round_response", message: "prepare_round response must include messages") unless response["messages"].is_a?(Array)
      raise ProtocolError.new(code: "invalid_prepare_round_response", message: "prepare_round response must include program_tools") unless response["program_tools"].is_a?(Array)
    end
  end
end
