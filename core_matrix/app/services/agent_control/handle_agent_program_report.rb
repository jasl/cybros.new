module AgentControl
  class HandleAgentProgramReport
    TERMINAL_METHODS = %w[agent_program_completed agent_program_failed].freeze

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
      }
    end

    def call
      ValidateAgentProgramReportFreshness.call(
        deployment: @deployment,
        method_id: @method_id,
        payload: @payload,
        mailbox_item: mailbox_item,
        occurred_at: @occurred_at
      )

      case @method_id
      when "agent_program_completed"
        mailbox_item.update!(
          status: "completed",
          acked_at: mailbox_item.acked_at || @occurred_at,
          completed_at: @occurred_at
        )
      when "agent_program_failed"
        mailbox_item.update!(
          status: "failed",
          acked_at: mailbox_item.acked_at || @occurred_at,
          failed_at: @occurred_at
        )
      else
        raise ArgumentError, "unsupported agent program report #{@method_id}"
      end
    end

    private

    def mailbox_item
      @mailbox_item ||= AgentControlMailboxItem.find_by!(
        installation_id: @deployment.installation_id,
        public_id: @payload.fetch("mailbox_item_id")
      )
    end
  end
end
