module Workflows
  class BlockNodeForFailure
    Result = Struct.new(
      :workflow_node,
      :workflow_run,
      :turn,
      :wait_reason_kind,
      :retry_strategy,
      :next_retry_at,
      :failure_category,
      :failure_kind,
      :attempt_no,
      :max_auto_retries,
      :terminal,
      keyword_init: true
    ) do
      def terminal?
        terminal
      end
    end

    DEFAULT_AUTOMATIC_RETRY_DELAYS = {
      "provider_overloaded" => 30.seconds,
      "provider_unreachable" => 30.seconds,
      "provider_rate_limited" => 15.seconds,
      "program_transport_failed" => 10.seconds,
      "execution_transport_failed" => 10.seconds,
      "tool_transport_failed" => 10.seconds,
      "tool_runtime_unavailable" => 10.seconds,
      "tool_invocation_timeout" => 10.seconds,
      "agent_session_unavailable" => 10.seconds,
      "execution_session_unavailable" => 10.seconds,
      "invalid_program_response_contract" => 5.seconds,
      "invalid_tool_call_contract" => 5.seconds,
      "invalid_tool_arguments" => 5.seconds,
      "unknown_tool_reference" => 5.seconds,
      "provider_round_limit_exceeded" => 5.seconds,
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, failure_category:, failure_kind:, retry_strategy: nil, max_auto_retries: 0, next_retry_at: nil, last_error_summary: nil, occurred_at: Time.current, metadata: {})
      @workflow_node = workflow_node
      @failure_category = failure_category.to_s
      @failure_kind = failure_kind.to_s
      @retry_strategy = retry_strategy&.to_s
      @max_auto_retries = max_auto_retries.to_i
      @requested_next_retry_at = next_retry_at
      @last_error_summary = last_error_summary.to_s
      @occurred_at = occurred_at
      @metadata = metadata.deep_stringify_keys
    end

    def call
      result = nil

      ApplicationRecord.transaction do
        @workflow_node.turn.with_lock do
          @workflow_node.workflow_run.with_lock do
            @workflow_node.with_lock do
              workflow_node = @workflow_node.reload
              workflow_run = workflow_node.workflow_run.reload
              turn = workflow_node.turn.reload

              result =
                if terminal_failure?
                  persist_terminal_failure!(workflow_node:, workflow_run:, turn:)
                else
                  persist_waiting_failure!(workflow_node:, workflow_run:, turn:)
                end
            end
          end
        end
      end

      schedule_automatic_resume!(result)
      result
    end

    private

    def terminal_failure?
      @failure_category == "implementation_error"
    end

    def persist_terminal_failure!(workflow_node:, workflow_run:, turn:)
      turn.update!(lifecycle_state: "failed")
      workflow_node.update!(
        lifecycle_state: "failed",
        started_at: workflow_node.started_at || @occurred_at,
        finished_at: @occurred_at,
        metadata: blocked_retry_metadata(workflow_node.metadata, attempt_no: nil)
      )
      append_status_event!(
        workflow_node: workflow_node,
        workflow_run: workflow_run,
        state: "failed",
        failure_category: @failure_category,
        failure_kind: @failure_kind,
        last_error_summary: @last_error_summary,
        **@metadata
      )
      workflow_run.update!(Workflows::WaitState.ready_attributes)
      Workflows::RefreshRunLifecycle.call(workflow_run: workflow_run, terminal_state: "failed")

      Result.new(
        workflow_node: workflow_node,
        workflow_run: workflow_run,
        turn: turn,
        failure_category: @failure_category,
        failure_kind: @failure_kind,
        wait_reason_kind: nil,
        retry_strategy: nil,
        next_retry_at: nil,
        attempt_no: nil,
        max_auto_retries: 0,
        terminal: true
      )
    end

    def persist_waiting_failure!(workflow_node:, workflow_run:, turn:)
      attempt_no = next_attempt_no_for(workflow_node)
      effective_retry_strategy = effective_retry_strategy_for(attempt_no)
      effective_next_retry_at = next_retry_at_for(effective_retry_strategy, attempt_no)
      wait_reason_kind = wait_reason_kind_for_failure_category

      workflow_node.update!(
        lifecycle_state: "waiting",
        started_at: workflow_node.started_at || @occurred_at,
        finished_at: nil,
        metadata: blocked_retry_metadata(workflow_node.metadata, attempt_no: attempt_no)
      )
      turn.update!(lifecycle_state: "waiting")
      workflow_run.update!(
        wait_state: "waiting",
        wait_reason_kind: wait_reason_kind,
        wait_reason_payload: {
          "failure_category" => @failure_category,
          "failure_kind" => @failure_kind,
          "retry_scope" => "step",
          "resume_mode" => "same_step",
          "retry_strategy" => effective_retry_strategy,
          "auto_retryable" => effective_retry_strategy == "automatic",
          "attempt_no" => attempt_no,
          "max_auto_retries" => @max_auto_retries,
          "next_retry_at" => effective_next_retry_at&.iso8601,
          "last_error_summary" => @last_error_summary,
        }.merge(@metadata).compact,
        waiting_since_at: @occurred_at,
        blocking_resource_type: "WorkflowNode",
        blocking_resource_id: workflow_node.public_id
      )
      append_status_event!(
        workflow_node: workflow_node,
        workflow_run: workflow_run,
        state: "waiting",
        failure_category: @failure_category,
        failure_kind: @failure_kind,
        retry_strategy: effective_retry_strategy,
        next_retry_at: effective_next_retry_at&.iso8601,
        attempt_no: attempt_no,
        max_auto_retries: @max_auto_retries,
        last_error_summary: @last_error_summary,
        **@metadata
      )

      Result.new(
        workflow_node: workflow_node,
        workflow_run: workflow_run,
        turn: turn,
        wait_reason_kind: wait_reason_kind,
        retry_strategy: effective_retry_strategy,
        next_retry_at: effective_next_retry_at,
        failure_category: @failure_category,
        failure_kind: @failure_kind,
        attempt_no: attempt_no,
        max_auto_retries: @max_auto_retries,
        terminal: false
      )
    end

    def next_attempt_no_for(workflow_node)
      retry_state = workflow_node.metadata.fetch("blocked_retry_state", {})
      if retry_state["failure_kind"] == @failure_kind
        retry_state["attempt_no"].to_i + 1
      else
        1
      end
    end

    def effective_retry_strategy_for(attempt_no)
      return nil if @retry_strategy.blank?
      return @retry_strategy unless @retry_strategy == "automatic"
      return "manual" if @max_auto_retries.positive? && attempt_no > @max_auto_retries

      "automatic"
    end

    def next_retry_at_for(retry_strategy, attempt_no)
      return nil unless retry_strategy == "automatic"
      return @requested_next_retry_at if @requested_next_retry_at.present?

      base_delay = DEFAULT_AUTOMATIC_RETRY_DELAYS.fetch(@failure_kind, 10.seconds)
      @occurred_at + (base_delay * [attempt_no, 1].max)
    end

    def wait_reason_kind_for_failure_category
      case @failure_category
      when "contract_error"
        "retryable_failure"
      when "external_dependency_blocked"
        "external_dependency_blocked"
      else
        nil
      end
    end

    def blocked_retry_metadata(metadata, attempt_no:)
      normalized = metadata.deep_dup
      if attempt_no.present?
        normalized["blocked_retry_state"] = {
          "failure_kind" => @failure_kind,
          "attempt_no" => attempt_no,
        }
      else
        normalized.delete("blocked_retry_state")
      end
      normalized
    end

    def append_status_event!(workflow_node:, workflow_run:, state:, **payload)
      WorkflowNodeEvent.create!(
        installation: workflow_run.installation,
        workflow_run: workflow_run,
        workflow_node: workflow_node,
        ordinal: workflow_node.workflow_node_events.maximum(:ordinal).to_i + 1,
        event_kind: "status",
        payload: payload.merge("state" => state)
      )
    end

    def schedule_automatic_resume!(result)
      return if result.blank? || result.terminal?
      return unless result.retry_strategy == "automatic"
      return if result.next_retry_at.blank?

      Workflows::ResumeBlockedStepJob.set(wait_until: result.next_retry_at).perform_later(result.workflow_run.public_id)
    end
  end
end
