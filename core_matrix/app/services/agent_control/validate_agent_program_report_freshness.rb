module AgentControl
  class ValidateAgentProgramReportFreshness
    TERMINAL_METHODS = %w[agent_program_completed agent_program_failed].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, method_id:, payload:, mailbox_item:, occurred_at: Time.current)
      @deployment = deployment
      @method_id = method_id
      @payload = payload
      @mailbox_item = mailbox_item
      @occurred_at = occurred_at
    end

    def call
      raise ArgumentError, "unsupported agent program freshness check #{@method_id}" unless TERMINAL_METHODS.include?(@method_id)

      stale! unless @mailbox_item.agent_program_request?
      stale! unless @mailbox_item.leased_to?(@deployment)
      stale! if @mailbox_item.lease_stale?(at: @occurred_at)
      stale! unless @mailbox_item.logical_work_id == @payload["logical_work_id"]
      stale! unless @mailbox_item.attempt_no == @payload["attempt_no"].to_i
      stale! unless @mailbox_item.leased? || @mailbox_item.acked?
    end

    private

    def stale!
      raise Report::StaleReportError
    end
  end
end
