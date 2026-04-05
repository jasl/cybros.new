module AgentControl
  class HandleAgentProgramReport
    TERMINAL_METHODS = %w[agent_program_completed agent_program_failed].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, method_id:, payload:, occurred_at: Time.current, **)
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
        complete_linked_conversation_control_request!("completed")
      when "agent_program_failed"
        mailbox_item.update!(
          status: "failed",
          acked_at: mailbox_item.acked_at || @occurred_at,
          failed_at: @occurred_at
        )
        complete_linked_conversation_control_request!("failed")
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

    def complete_linked_conversation_control_request!(lifecycle_state)
      control_request = linked_conversation_control_request
      return if control_request.blank?

      control_request.update!(
        lifecycle_state: lifecycle_state,
        completed_at: @occurred_at,
        result_payload: control_request.result_payload.merge(
          "mailbox_item_id" => mailbox_item.public_id,
          "mailbox_status" => mailbox_item.status,
          "mailbox_completed_at" => mailbox_item.completed_at&.iso8601,
          "mailbox_failed_at" => mailbox_item.failed_at&.iso8601
        ).compact
      )
    end

    def linked_conversation_control_request
      control_request_public_id = mailbox_item.payload.dig("conversation_control", "conversation_control_request_id")
      return if control_request_public_id.blank?

      ConversationControlRequest.find_by(
        installation_id: mailbox_item.installation_id,
        public_id: control_request_public_id
      )
    end
  end
end
