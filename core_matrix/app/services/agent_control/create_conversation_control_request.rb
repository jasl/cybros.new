module AgentControl
  class CreateConversationControlRequest
    def self.call(...)
      new(...).call
    end

    def initialize(conversation_control_request:, agent_program_version:, request_kind:, payload:, dispatch_deadline_at:, execution_hard_deadline_at: nil)
      @conversation_control_request = conversation_control_request
      @agent_program_version = agent_program_version
      @request_kind = request_kind.to_s
      @payload = payload.deep_stringify_keys
      @dispatch_deadline_at = dispatch_deadline_at
      @execution_hard_deadline_at = execution_hard_deadline_at
    end

    def call
      mailbox_item = AgentControl::CreateAgentProgramRequest.call(
        agent_program_version: @agent_program_version,
        request_kind: @request_kind,
        payload: @payload.merge("conversation_control" => conversation_control_payload),
        logical_work_id: "conversation-control:#{@conversation_control_request.public_id}:#{@request_kind}",
        attempt_no: 1,
        dispatch_deadline_at: @dispatch_deadline_at,
        execution_hard_deadline_at: @execution_hard_deadline_at
      )

      @conversation_control_request.update!(
        lifecycle_state: "dispatched",
        result_payload: @conversation_control_request.result_payload.merge(
          "dispatch_kind" => "agent_program_request",
          "mailbox_item_id" => mailbox_item.public_id,
          "mailbox_request_kind" => mailbox_item.payload.fetch("request_kind"),
          "mailbox_status" => mailbox_item.status,
          "target_agent_program_version_id" => mailbox_item.target_agent_program_version&.public_id
        ).compact
      )

      mailbox_item
    end

    private

    def conversation_control_payload
      {
        "conversation_control_request_id" => @conversation_control_request.public_id,
        "conversation_id" => @conversation_control_request.target_conversation.public_id,
        "request_kind" => @conversation_control_request.request_kind,
        "target_kind" => @conversation_control_request.target_kind,
        "target_public_id" => @conversation_control_request.target_public_id
      }.compact
    end
  end
end
