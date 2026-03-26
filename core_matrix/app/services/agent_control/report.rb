module AgentControl
  class Report
    StaleReportError = Class.new(StandardError)

    Result = Struct.new(:code, :http_status, :mailbox_items, keyword_init: true)

    RESOURCE_TYPES = {
      "AgentTaskRun" => AgentTaskRun,
      "ProcessRun" => ProcessRun,
      "SubagentRun" => SubagentRun,
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, method_id: nil, message_id: nil, payload: nil, occurred_at: Time.current, **kwargs)
      raw_payload = payload.presence || kwargs
      @deployment = deployment
      @payload = raw_payload.deep_stringify_keys
      @method_id = method_id || @payload.fetch("method_id")
      @message_id = message_id || @payload.fetch("message_id")
      @occurred_at = occurred_at
    end

    def call
      TouchDeploymentActivity.call(deployment: @deployment, occurred_at: @occurred_at)

      existing_receipt = find_existing_receipt
      return duplicate_result_for(existing_receipt) if existing_receipt.present?

      receipt = create_receipt!

      begin
        process_report!(receipt)
        receipt.update!(result_code: "accepted")
        Result.new(
          code: "accepted",
          http_status: :ok,
          mailbox_items: Poll.call(deployment: @deployment, limit: Poll::DEFAULT_LIMIT, occurred_at: @occurred_at)
        )
      rescue StaleReportError
        receipt.update!(result_code: "stale")
        Result.new(code: "stale", http_status: :conflict, mailbox_items: [])
      end
    rescue ActiveRecord::RecordNotUnique
      duplicate_result_for(find_existing_receipt)
    end

    private

    def duplicate_result_for(receipt)
      code = receipt.result_code == "accepted" ? "duplicate" : receipt.result_code
      Result.new(
        code: code,
        http_status: code == "stale" ? :conflict : :ok,
        mailbox_items: code == "stale" ? [] : Poll.call(deployment: @deployment, limit: Poll::DEFAULT_LIMIT, occurred_at: @occurred_at)
      )
    end

    def create_receipt!
      AgentControlReportReceipt.create!(
        installation: @deployment.installation,
        agent_deployment: @deployment,
        message_id: @message_id,
        method_id: @method_id,
        logical_work_id: @payload["logical_work_id"],
        attempt_no: @payload["attempt_no"],
        result_code: "processing",
        payload: @payload
      )
    end

    def find_existing_receipt
      AgentControlReportReceipt.find_by(installation_id: @deployment.installation_id, message_id: @message_id)
    end

    def process_report!(receipt)
      case @method_id
      when "deployment_health_report"
        handle_deployment_health_report!
      when "execution_started"
        receipt.update!(mailbox_item: mailbox_item, agent_task_run: agent_task_run)
        handle_execution_started!
      when "execution_progress"
        receipt.update!(mailbox_item: mailbox_item, agent_task_run: agent_task_run)
        handle_execution_progress!
      when "execution_complete", "execution_fail", "execution_interrupted"
        receipt.update!(mailbox_item: mailbox_item, agent_task_run: agent_task_run)
        handle_execution_terminal!
      when "resource_close_acknowledged"
        receipt.update!(mailbox_item: mailbox_item)
        handle_resource_close_acknowledged!
      when "resource_closed", "resource_close_failed"
        receipt.update!(mailbox_item: mailbox_item)
        handle_resource_close_terminal!
      else
        raise ArgumentError, "unknown control report #{@method_id}"
      end
    end

    def handle_deployment_health_report!
      @deployment.update!(
        health_status: @payload.fetch("health_status"),
        health_metadata: @payload.fetch("health_metadata", {}),
        last_health_check_at: @occurred_at
      )
    end

    def handle_execution_started!
      ensure_assignment_offer_fresh!

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
      ensure_active_execution_holder!
      heartbeat_task_lease!
      agent_task_run.update!(progress_payload: @payload.fetch("progress_payload", {}))
    end

    def handle_execution_terminal!
      ensure_active_execution_holder!
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

    def handle_resource_close_acknowledged!
      resource = closable_resource
      ensure_close_request_fresh!(resource)
      resource.update!(close_state: "acknowledged", close_acknowledged_at: @occurred_at)
      mailbox_item.update!(status: "acked", acked_at: @occurred_at)
    end

    def handle_resource_close_terminal!
      resource = closable_resource
      ensure_close_request_fresh!(resource)

      resource.update!(
        close_state: @method_id == "resource_closed" ? "closed" : "failed",
        close_acknowledged_at: resource.close_acknowledged_at || @occurred_at,
        close_outcome_kind: @payload.fetch("close_outcome_kind"),
        close_outcome_payload: @payload.fetch("close_outcome_payload", {})
      )
      mailbox_item.update!(status: "completed", completed_at: @occurred_at)
    end

    def terminal_payload_for_terminal_message
      payload = @payload.fetch("terminal_payload", {}).deep_stringify_keys
      payload["terminal_method_id"] = @method_id
      payload
    end

    def ensure_assignment_offer_fresh!
      raise StaleReportError unless mailbox_item.execution_assignment?
      raise StaleReportError unless mailbox_item.leased_to?(@deployment)
      raise StaleReportError if mailbox_item.lease_stale?(at: @occurred_at)
      raise StaleReportError unless mailbox_item.agent_task_run_id == agent_task_run.id
      raise StaleReportError unless mailbox_item.logical_work_id == @payload["logical_work_id"]
      raise StaleReportError unless mailbox_item.attempt_no == @payload["attempt_no"].to_i
      raise StaleReportError unless agent_task_run.queued?
    end

    def ensure_active_execution_holder!
      raise StaleReportError unless mailbox_item.agent_task_run_id == agent_task_run.id
      raise StaleReportError unless agent_task_run.logical_work_id == @payload["logical_work_id"]
      raise StaleReportError unless agent_task_run.attempt_no == @payload["attempt_no"].to_i
      raise StaleReportError unless agent_task_run.running?
      raise StaleReportError unless agent_task_run.holder_agent_deployment_id == @deployment.id
      raise StaleReportError unless agent_task_run.execution_lease&.active?
    end

    def heartbeat_task_lease!
      Leases::Heartbeat.call(
        execution_lease: agent_task_run.execution_lease,
        holder_key: @deployment.public_id,
        occurred_at: @occurred_at
      )
    rescue ArgumentError, Leases::Heartbeat::StaleLeaseError
      raise StaleReportError
    end

    def ensure_close_request_fresh!(resource)
      raise StaleReportError unless mailbox_item.resource_close_request?
      raise StaleReportError unless mailbox_item.leased_to?(@deployment) || mailbox_item.acked?
      raise StaleReportError unless mailbox_item.payload["resource_type"] == resource.class.name
      raise StaleReportError unless mailbox_item.payload["resource_id"] == resource.public_id
      raise StaleReportError unless mailbox_item.public_id == @payload["close_request_id"]
      raise StaleReportError unless resource.close_requested_at.present?
      raise StaleReportError if resource.close_closed? || resource.close_failed?
    end

    def agent_task_run
      @agent_task_run ||= AgentTaskRun.find_by!(
        installation_id: @deployment.installation_id,
        public_id: @payload.fetch("agent_task_run_id")
      )
    end

    def mailbox_item
      @mailbox_item ||= AgentControlMailboxItem.find_by!(
        installation_id: @deployment.installation_id,
        public_id: @payload.fetch("mailbox_item_id")
      )
    end

    def closable_resource
      resource_type = @payload.fetch("resource_type")
      resource_class = RESOURCE_TYPES.fetch(resource_type)
      resource_class.find_by!(
        installation_id: @deployment.installation_id,
        public_id: @payload.fetch("resource_id")
      )
    end
  end
end
