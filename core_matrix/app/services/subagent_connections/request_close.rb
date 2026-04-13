module SubagentConnections
  class RequestClose
    GRACE_PERIOD = Conversations::RequestResourceCloses::GRACE_PERIOD
    FORCE_PERIOD = Conversations::RequestResourceCloses::FORCE_PERIOD

    def self.call(...)
      new(...).call
    end

    def initialize(subagent_connection:, request_kind:, reason_kind:, strictness:, publish_delivery_endpoint: nil, occurred_at: Time.current, conversation_control_request: nil)
      @subagent_connection = subagent_connection
      @request_kind = request_kind
      @reason_kind = reason_kind
      @strictness = strictness
      @publish_delivery_endpoint = publish_delivery_endpoint
      @occurred_at = occurred_at
      @conversation_control_request = conversation_control_request
    end

    def call
      unless @subagent_connection.close_open?
        session = @subagent_connection
        complete_control_request!(session)
        return session
      end

      AgentControl::CreateResourceCloseRequest.call(
        resource: @subagent_connection,
        request_kind: @request_kind,
        reason_kind: @reason_kind,
        strictness: @strictness,
        publish_delivery_endpoint: @publish_delivery_endpoint,
        grace_deadline_at: anchor_time + GRACE_PERIOD,
        force_deadline_at: anchor_time + FORCE_PERIOD
      )

      session = @subagent_connection
      complete_control_request!(session)
      session
    end

    private

    def anchor_time
      @anchor_time ||= [@occurred_at, Time.current].max
    end

    def complete_control_request!(session)
      return if @conversation_control_request.blank?

      @conversation_control_request.update!(
        lifecycle_state: "completed",
        completed_at: @occurred_at,
        result_payload: @conversation_control_request.result_payload.merge(
          "subagent_connection_id" => session.public_id,
          "conversation_id" => session.conversation.public_id
        )
      )
    end
  end
end
