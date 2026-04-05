module SubagentSessions
  class RequestClose
    GRACE_PERIOD = Conversations::RequestResourceCloses::GRACE_PERIOD
    FORCE_PERIOD = Conversations::RequestResourceCloses::FORCE_PERIOD

    def self.call(...)
      new(...).call
    end

    def initialize(subagent_session:, request_kind:, reason_kind:, strictness:, publish_delivery_endpoint: nil, occurred_at: Time.current)
      @subagent_session = subagent_session
      @request_kind = request_kind
      @reason_kind = reason_kind
      @strictness = strictness
      @publish_delivery_endpoint = publish_delivery_endpoint
      @occurred_at = occurred_at
    end

    def call
      return @subagent_session.reload unless @subagent_session.close_open?

      AgentControl::CreateResourceCloseRequest.call(
        resource: @subagent_session,
        request_kind: @request_kind,
        reason_kind: @reason_kind,
        strictness: @strictness,
        publish_delivery_endpoint: @publish_delivery_endpoint,
        grace_deadline_at: anchor_time + GRACE_PERIOD,
        force_deadline_at: anchor_time + FORCE_PERIOD
      )

      @subagent_session.reload
    end

    private

    def anchor_time
      @anchor_time ||= [@occurred_at, Time.current].max
    end
  end
end
