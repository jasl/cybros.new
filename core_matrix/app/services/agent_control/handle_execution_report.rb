module AgentControl
  class HandleExecutionReport
    TERMINAL_METHODS = %w[execution_complete execution_fail execution_interrupted].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, method_id:, payload:, occurred_at: Time.current)
      @deployment = deployment
      @method_id = method_id
      @payload = payload
      @occurred_at = occurred_at
    end

    def receipt_attributes
      {
        mailbox_item: mailbox_item,
        agent_task_run: agent_task_run,
      }
    end

    def call
      ValidateExecutionReportFreshness.call(
        deployment: @deployment,
        method_id: @method_id,
        payload: @payload,
        mailbox_item: mailbox_item,
        agent_task_run: agent_task_run,
        occurred_at: @occurred_at
      )

      case @method_id
      when "execution_started"
        handle_execution_started!
      when "execution_progress"
        handle_execution_progress!
      when *TERMINAL_METHODS
        handle_execution_terminal!
      else
        raise ArgumentError, "unsupported execution report #{@method_id}"
      end
    end

    private

    def handle_execution_started!
      agent_task_run.update!(
        lifecycle_state: "running",
        started_at: @occurred_at,
        holder_agent_deployment: @deployment,
        expected_duration_seconds: @payload["expected_duration_seconds"]
      )

      unless agent_task_run.execution_lease&.active?
        Leases::Acquire.call(
          leased_resource: agent_task_run,
          holder_key: @deployment.public_id,
          heartbeat_timeout_seconds: mailbox_item.lease_timeout_seconds
        )
      end

      mailbox_item.update!(status: "acked", acked_at: @occurred_at)
    end

    def handle_execution_progress!
      heartbeat_task_lease!
      agent_task_run.update!(progress_payload: @payload.fetch("progress_payload", {}))
    end

    def handle_execution_terminal!
      heartbeat_task_lease!

      lifecycle_state = case @method_id
      when "execution_complete" then "completed"
      when "execution_fail" then "failed"
      else "interrupted"
      end

      agent_task_run.update!(
        lifecycle_state: lifecycle_state,
        terminal_payload: terminal_payload_for_terminal_message,
        finished_at: @occurred_at
      )

      apply_retry_gate! if lifecycle_state == "failed"

      if agent_task_run.execution_lease&.active?
        Leases::Release.call(
          execution_lease: agent_task_run.execution_lease,
          holder_key: @deployment.public_id,
          reason: lifecycle_state,
          released_at: @occurred_at
        )
      end

      mailbox_item.update!(status: "completed", completed_at: @occurred_at)
    end

    def terminal_payload_for_terminal_message
      payload = @payload.fetch("terminal_payload", {}).deep_stringify_keys
      payload["terminal_method_id"] = @method_id
      payload
    end

    def heartbeat_task_lease!
      Leases::Heartbeat.call(
        execution_lease: agent_task_run.execution_lease,
        holder_key: @deployment.public_id,
        occurred_at: @occurred_at
      )
    rescue ArgumentError, Leases::Heartbeat::StaleLeaseError
      raise Report::StaleReportError
    end

    def apply_retry_gate!
      terminal_payload = agent_task_run.terminal_payload
      return unless terminal_payload["retryable"]
      return unless terminal_payload["retry_scope"] == "step"

      agent_task_run.workflow_run.update!(
        wait_state: "waiting",
        wait_reason_kind: "retryable_failure",
        wait_reason_payload: {
          "failure_kind" => terminal_payload["failure_kind"],
          "retryable" => true,
          "retry_scope" => "step",
          "logical_work_id" => agent_task_run.logical_work_id,
          "attempt_no" => agent_task_run.attempt_no,
          "last_error_summary" => terminal_payload["last_error_summary"],
        }.compact,
        waiting_since_at: @occurred_at,
        blocking_resource_type: "AgentTaskRun",
        blocking_resource_id: agent_task_run.public_id
      )
    end

    def mailbox_item
      @mailbox_item ||= AgentControlMailboxItem.find_by!(
        installation_id: @deployment.installation_id,
        public_id: @payload.fetch("mailbox_item_id")
      )
    end

    def agent_task_run
      @agent_task_run ||= AgentTaskRun.find_by!(
        installation_id: @deployment.installation_id,
        public_id: @payload.fetch("agent_task_run_id")
      )
    end
  end
end
