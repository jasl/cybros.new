module AgentControl
  class HandleAgentReport
    TERMINAL_METHODS = %w[agent_completed agent_failed].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(agent_snapshot:, method_id:, payload:, occurred_at: Time.current, **)
      @agent_snapshot = agent_snapshot
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
      ValidateAgentReportFreshness.call(
        agent_snapshot: @agent_snapshot,
        method_id: @method_id,
        payload: @payload,
        mailbox_item: mailbox_item,
        occurred_at: @occurred_at
      )

      case @method_id
      when "agent_completed"
        mailbox_item.update!(
          status: "completed",
          acked_at: mailbox_item.acked_at || @occurred_at,
          completed_at: @occurred_at
        )
        complete_linked_conversation_control_request!("completed")
        resume_blocked_workflow!
      when "agent_failed"
        mailbox_item.update!(
          status: "failed",
          acked_at: mailbox_item.acked_at || @occurred_at,
          failed_at: @occurred_at
        )
        complete_linked_conversation_control_request!("failed")
        resume_blocked_workflow!
      else
        raise ArgumentError, "unsupported agent report #{@method_id}"
      end
    end

    private

    def mailbox_item
      @mailbox_item ||= AgentControlMailboxItem.find_by!(
        installation_id: @agent_snapshot.installation_id,
        public_id: @payload.fetch("mailbox_item_id")
      )
    end

    def complete_linked_conversation_control_request!(lifecycle_state)
      control_request = linked_conversation_control_request
      return if control_request.blank?

      result_payload = control_request.result_payload.merge(
        "mailbox_item_id" => mailbox_item.public_id,
        "mailbox_status" => mailbox_item.status,
        "mailbox_completed_at" => mailbox_item.completed_at&.iso8601,
        "mailbox_failed_at" => mailbox_item.failed_at&.iso8601
      ).compact
      response_payload = @payload["response_payload"]
      error_payload = @payload["error_payload"]
      result_payload["response_payload"] = response_payload.deep_stringify_keys if response_payload.is_a?(Hash)
      result_payload["error_payload"] = error_payload.deep_stringify_keys if error_payload.is_a?(Hash)

      control_request.update!(
        lifecycle_state: lifecycle_state,
        completed_at: @occurred_at,
        result_payload:
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

    def resume_blocked_workflow!
      workflow_node = mailbox_item.workflow_node
      return if workflow_node.blank?

      workflow_run = workflow_node.workflow_run
      return unless workflow_run.waiting?
      return unless workflow_run.wait_reason_kind == "agent_request"
      return unless workflow_run.blocking_resource_type == "WorkflowNode"
      return unless workflow_run.blocking_resource_id == workflow_node.public_id

      Workflows::ResumeBlockedStep.call(workflow_run: workflow_run)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
      nil
    end
  end
end
