module AgentControl
  class ValidateAgentReportFreshness
    TERMINAL_METHODS = %w[agent_completed agent_failed].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, method_id:, payload:, mailbox_item:, occurred_at: Time.current)
      @agent_definition_version = agent_definition_version
      @method_id = method_id
      @payload = payload
      @mailbox_item = mailbox_item
      @occurred_at = occurred_at
    end

    def call
      raise ArgumentError, "unsupported agent freshness check #{@method_id}" unless TERMINAL_METHODS.include?(@method_id)

      stale! unless @mailbox_item.agent_request?
      stale! unless @mailbox_item.leased_to?(@agent_definition_version)
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
