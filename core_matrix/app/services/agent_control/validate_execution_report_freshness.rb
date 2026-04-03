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

    def initialize(deployment:, agent_session: nil, method_id:, payload:, mailbox_item:, agent_task_run:, occurred_at: Time.current)
      @deployment = deployment
      @agent_session = agent_session
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
      stale! unless @mailbox_item.leased_to?(@deployment)
      stale! if @mailbox_item.lease_stale?(at: @occurred_at)
      stale! unless @mailbox_item.agent_task_run_id == @agent_task_run.id
      stale! unless @mailbox_item.logical_work_id == @payload["logical_work_id"]
      stale! unless @mailbox_item.attempt_no == @payload["attempt_no"].to_i
      stale! unless @agent_task_run.queued?
    end

    def validate_active_execution_holder!
      stale! unless @mailbox_item.agent_task_run_id == @agent_task_run.id
      stale! unless @agent_task_run.logical_work_id == @payload["logical_work_id"]
      stale! unless @agent_task_run.attempt_no == @payload["attempt_no"].to_i
      stale! unless @agent_task_run.running?
      stale! unless @agent_task_run.holder_agent_session_id == resolved_agent_session&.id
      stale! unless @agent_task_run.execution_lease&.active?
      stale! if @agent_task_run.close_requested_at.present?
    end

    def resolved_agent_session
      @resolved_agent_session ||= @agent_session || @deployment.active_agent_session || @deployment.most_recent_agent_session
    end

    def stale!
      raise Report::StaleReportError
    end
  end
end
