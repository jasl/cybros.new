require "securerandom"

module ProviderExecution
  class ProgramMailboxExchange
    DEFAULT_PREPARE_ROUND_TIMEOUT = 30.seconds
    DEFAULT_EXECUTE_PROGRAM_TOOL_TIMEOUT = 5.minutes
    DEFAULT_TOOL_TIMEOUT_BUFFER = 30.seconds
    DEFAULT_LEASE_GRACE = 10.seconds
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

    class ProtocolError < ExchangeError; end
    class TimeoutError < ExchangeError; end
    class PendingResponse < StandardError
      attr_reader :mailbox_item_public_id, :logical_work_id, :request_kind

      def initialize(mailbox_item_public_id:, logical_work_id:, request_kind:)
        @mailbox_item_public_id = mailbox_item_public_id
        @logical_work_id = logical_work_id
        @request_kind = request_kind
        super("agent program request #{request_kind} is pending for mailbox item #{mailbox_item_public_id}")
      end
    end
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

    def initialize(
      agent_program_version:,
      timeout: nil,
      prepare_round_timeout: DEFAULT_PREPARE_ROUND_TIMEOUT,
      execute_program_tool_timeout: DEFAULT_EXECUTE_PROGRAM_TOOL_TIMEOUT,
      tool_timeout_buffer: DEFAULT_TOOL_TIMEOUT_BUFFER,
      lease_grace: DEFAULT_LEASE_GRACE,
      poll_interval: DEFAULT_POLL_INTERVAL,
      sleeper: nil
    )
      @agent_program_version = agent_program_version
      @prepare_round_timeout = timeout || prepare_round_timeout
      @execute_program_tool_timeout = timeout || execute_program_tool_timeout
      @tool_timeout_buffer = tool_timeout_buffer
      @lease_grace = lease_grace
      @poll_interval = poll_interval
      @sleeper = sleeper || ->(duration) { sleep(duration) }
    end

    def prepare_round(payload:)
      response = perform_request!(
        request_kind: "prepare_round",
        payload:,
        logical_work_id: "prepare-round:#{payload.fetch("task").fetch("workflow_node_id")}",
        timeout: @prepare_round_timeout
      )
      validate_prepare_round_response!(response)
      response
    end

    def execute_program_tool(payload:)
      perform_request!(
        request_kind: "execute_program_tool",
        payload:,
        logical_work_id: "program-tool:#{payload.fetch("task").fetch("workflow_node_id")}:#{payload.fetch("program_tool_call").fetch("call_id")}",
        timeout: execute_program_tool_timeout_for(payload),
        allow_failure_response: true
      )
    end

    private

    TERMINAL_METHODS = %w[agent_program_completed agent_program_failed].freeze
    PENDING_METADATA_KEY = Workflows::BlockNodeForProgramRequest::METADATA_KEY

    def perform_request!(request_kind:, payload:, logical_work_id:, timeout:, allow_failure_response: false)
      timeout = timeout.to_f.seconds
      workflow_node = resolved_workflow_node_for(payload)
      raise ProtocolError.new(code: "missing_workflow_node_id", message: "agent program requests must target a workflow node") if workflow_node.blank?

      pending_state = pending_exchange_state_for(workflow_node, request_kind:, logical_work_id:)
      if pending_state.present?
        mailbox_item = pending_mailbox_item_for!(workflow_node, pending_state)
        return resolve_pending_request!(
          workflow_node: workflow_node,
          mailbox_item: mailbox_item,
          request_kind: request_kind,
          logical_work_id: logical_work_id,
          allow_failure_response: allow_failure_response
        )
      end

      request_started_at = Time.current
      mailbox_item = AgentControl::CreateAgentProgramRequest.call(
        agent_program_version: @agent_program_version,
        request_kind: request_kind,
        payload: payload,
        logical_work_id: logical_work_id,
        attempt_no: 1,
        dispatch_deadline_at: request_started_at + timeout,
        execution_hard_deadline_at: request_started_at + timeout,
        lease_timeout_seconds: [timeout.to_f.ceil + @lease_grace.to_i, 1].max
      )
      receipt = terminal_receipt_for(mailbox_item)
      return terminal_response_for(
        workflow_node: workflow_node,
        mailbox_item: mailbox_item,
        receipt: receipt,
        request_kind: request_kind,
        allow_failure_response: allow_failure_response
      ) if receipt.present?

      Workflows::BlockNodeForProgramRequest.call(
        workflow_node: workflow_node,
        mailbox_item: mailbox_item,
        request_kind: request_kind,
        logical_work_id: logical_work_id,
        deadline_at: mailbox_item.dispatch_deadline_at,
        occurred_at: request_started_at
      )
      raise PendingResponse.new(
        mailbox_item_public_id: mailbox_item.public_id,
        logical_work_id: logical_work_id,
        request_kind: request_kind
      )
    end

    def resolve_pending_request!(workflow_node:, mailbox_item:, request_kind:, logical_work_id:, allow_failure_response:)
      receipt = terminal_receipt_for(mailbox_item)
      return terminal_response_for(
        workflow_node: workflow_node,
        mailbox_item: mailbox_item,
        receipt: receipt,
        request_kind: request_kind,
        allow_failure_response: allow_failure_response
      ) if receipt.present?

      if request_timed_out?(mailbox_item)
        clear_pending_exchange_state!(workflow_node)
        publish_wait_event!(
          mailbox_item: mailbox_item,
          request_kind: request_kind,
          success: false,
          started_at: mailbox_item.created_at || mailbox_item.available_at || Time.current,
          finished_at: Time.current
        )
        raise TimeoutError.new(
          code: "mailbox_timeout",
          message: "timed out waiting for agent program report",
          details: { "mailbox_item_id" => mailbox_item.public_id },
          retryable: true
        )
      end

      Workflows::BlockNodeForProgramRequest.call(
        workflow_node: workflow_node,
        mailbox_item: mailbox_item,
        request_kind: request_kind,
        logical_work_id: logical_work_id,
        deadline_at: mailbox_item.dispatch_deadline_at || mailbox_item.execution_hard_deadline_at,
        occurred_at: Time.current
      )
      raise PendingResponse.new(
        mailbox_item_public_id: mailbox_item.public_id,
        logical_work_id: logical_work_id,
        request_kind: request_kind
      )
    end

    def terminal_response_for(workflow_node:, mailbox_item:, receipt:, request_kind:, allow_failure_response:)
      clear_pending_exchange_state!(workflow_node)
      publish_wait_event!(
        mailbox_item: mailbox_item,
        request_kind: request_kind,
        success: receipt.payload.fetch("method_id") == "agent_program_completed",
        started_at: mailbox_item.created_at || mailbox_item.available_at || Time.current,
        finished_at: receipt.created_at || Time.current
      )
      report_payload = receipt.payload.deep_stringify_keys

      return report_payload.fetch("response_payload") if report_payload.fetch("method_id") == "agent_program_completed"
      return { "status" => "failed", "failure" => report_payload.fetch("error_payload") } if allow_failure_response

      raise RequestFailed.new(
        error_payload: report_payload.fetch("error_payload"),
        details: { "mailbox_item_id" => mailbox_item.public_id, "request_kind" => request_kind }
      )
    end

    def resolved_workflow_node_for(payload)
      workflow_node_public_id = payload.dig("task", "workflow_node_id")
      return if workflow_node_public_id.blank?

      WorkflowNode.find_by!(
        installation_id: @agent_program_version.installation_id,
        public_id: workflow_node_public_id
      )
    end

    def pending_exchange_state_for(workflow_node, request_kind:, logical_work_id:)
      state = workflow_node.metadata.fetch(PENDING_METADATA_KEY, nil)
      return unless state.is_a?(Hash)
      return unless state["request_kind"] == request_kind
      return unless state["logical_work_id"] == logical_work_id

      state
    end

    def pending_mailbox_item_for!(workflow_node, pending_state)
      AgentControlMailboxItem.find_by!(
        installation_id: workflow_node.installation_id,
        workflow_node: workflow_node,
        public_id: pending_state.fetch("mailbox_item_id"),
        item_type: "agent_program_request"
      )
    rescue ActiveRecord::RecordNotFound
      clear_pending_exchange_state!(workflow_node)
      raise ProtocolError.new(
        code: "missing_mailbox_request",
        message: "pending agent program request is missing its mailbox item",
        details: { "workflow_node_id" => workflow_node.public_id }
      )
    end

    def terminal_receipt_for(mailbox_item)
      AgentControlReportReceipt.uncached do
        AgentControlReportReceipt.find_by(mailbox_item_id: mailbox_item.id, method_id: TERMINAL_METHODS)
      end
    end

    def request_timed_out?(mailbox_item)
      deadline_at = mailbox_item.dispatch_deadline_at || mailbox_item.execution_hard_deadline_at
      deadline_at.present? && Time.current >= deadline_at
    end

    def clear_pending_exchange_state!(workflow_node)
      metadata = workflow_node.metadata
      return unless metadata.key?(PENDING_METADATA_KEY)

      workflow_node.update!(metadata: metadata.except(PENDING_METADATA_KEY))
    end

    def publish_wait_event!(mailbox_item:, request_kind:, success:, started_at:, finished_at:)
      event = ActiveSupport::Notifications::Event.new(
        "perf.provider_execution.program_mailbox_exchange_wait",
        started_at,
        finished_at,
        SecureRandom.uuid,
        {
          "agent_program_public_id" => @agent_program_version.agent_program.public_id,
          "mailbox_item_public_id" => mailbox_item.public_id,
          "request_kind" => request_kind,
          "success" => success,
        }
      )
      ActiveSupport::Notifications.publish_event(event)
    end

    def wait_for_terminal_receipt!(mailbox_item, timeout:, event_payload: nil)
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout.to_f
      poll_attempt = 0

      loop do
        receipt = AgentControlReportReceipt.uncached do
          AgentControlReportReceipt.find_by(mailbox_item_id: mailbox_item.id, method_id: TERMINAL_METHODS)
        end
        if receipt.present?
          event_payload["poll_attempts"] = poll_attempt if event_payload
          return receipt
        end

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
          event_payload["poll_attempts"] = poll_attempt if event_payload
          raise TimeoutError.new(
            code: "mailbox_timeout",
            message: "timed out waiting for agent program report",
            details: { "mailbox_item_id" => mailbox_item.public_id },
            retryable: true
          )
        end

        poll_attempt += 1
        event_payload["poll_attempts"] = poll_attempt if event_payload
        @sleeper.call(poll_interval_for_attempt(poll_attempt))
      end
    end

    def execute_program_tool_timeout_for(payload)
      requested_timeout_seconds = payload.dig("program_tool_call", "arguments", "timeout_seconds").to_f
      return @execute_program_tool_timeout if requested_timeout_seconds <= 0

      [@execute_program_tool_timeout.to_f, requested_timeout_seconds + @tool_timeout_buffer.to_f].max.seconds
    end

    def validate_prepare_round_response!(response)
      raise ProtocolError.new(code: "invalid_prepare_round_response", message: "prepare_round response must include messages") unless response["messages"].is_a?(Array)
      raise ProtocolError.new(code: "invalid_prepare_round_response", message: "prepare_round response must include visible_tool_names") unless response["visible_tool_names"].is_a?(Array)
    end

    def poll_interval_for_attempt(poll_attempt)
      return @poll_interval if @poll_interval.to_f <= 0

      exponent = [poll_attempt - 1, 4].min
      [@poll_interval * (2**exponent), MAX_POLL_INTERVAL].min
    end
  end
end
