module AgentControl
  class ValidateExecutionReportFreshness
    ACTIVE_METHODS = %w[
      execution_progress
      execution_complete
      execution_fail
      execution_interrupted
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(
      agent_definition_version:,
      agent_connection: nil,
      execution_runtime_connection: nil,
      method_id:,
      payload:,
      mailbox_item:,
      agent_task_run:,
      occurred_at: Time.current
    )
      @agent_definition_version = agent_definition_version
      @agent_connection = agent_connection
      @execution_runtime_connection = execution_runtime_connection
      @method_id = method_id
      @payload = payload
      @mailbox_item = mailbox_item
      @agent_task_run = agent_task_run
      @occurred_at = occurred_at
    end

    def call
      case @method_id
      when "execution_started"
        validate_offer_fresh!
      when *ACTIVE_METHODS
        validate_active_execution_holder!
      else
        raise ArgumentError, "unsupported execution freshness check #{@method_id}"
      end
    end

    private

    def validate_offer_fresh!
      stale! unless @mailbox_item.execution_assignment?
      stale! unless @mailbox_item.leased_to?(lease_owner)
      stale! if @mailbox_item.lease_stale?(at: @occurred_at)
      stale! unless @mailbox_item.agent_task_run_id == @agent_task_run.id
      stale! unless @mailbox_item.logical_work_id == @payload["logical_work_id"]
      stale! unless @mailbox_item.attempt_no == @payload["attempt_no"].to_i
      stale! unless @agent_task_run.queued?
      validate_execution_runtime_alignment! if @mailbox_item.execution_runtime_plane?
    end

    def validate_active_execution_holder!
      stale! unless @mailbox_item.agent_task_run_id == @agent_task_run.id
      stale! unless @agent_task_run.logical_work_id == @payload["logical_work_id"]
      stale! unless @agent_task_run.attempt_no == @payload["attempt_no"].to_i
      stale! unless @agent_task_run.running?
      stale! unless @agent_task_run.holder_agent_connection_id == resolved_agent_connection&.id
      stale! unless @agent_task_run.execution_lease&.active?
      stale! if @agent_task_run.close_requested_at.present?
      validate_execution_runtime_alignment! if @mailbox_item.execution_runtime_plane?
    end

    def validate_execution_runtime_alignment!
      runtime_id = @mailbox_item.target_execution_runtime_id
      stale! if runtime_id.blank?

      if @execution_runtime_connection.present?
        stale! unless @execution_runtime_connection.execution_runtime_id == runtime_id
      else
        stale! unless ExecutionRuntimeConnection.exists?(execution_runtime_id: runtime_id, lifecycle_state: "active")
      end
    end

    def lease_owner
      return @execution_runtime_connection if @mailbox_item.execution_runtime_plane?

      @agent_definition_version
    end

    def resolved_agent_connection
      @resolved_agent_connection ||= @agent_connection || @agent_definition_version.active_agent_connection || @agent_definition_version.most_recent_agent_connection
    end

    def stale!
      raise Report::StaleReportError
    end
  end
end
