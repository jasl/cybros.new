module AgentControl
  class HandleHealthReport
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, agent_session: nil, payload:, occurred_at: Time.current, **)
      @deployment = deployment
      @agent_session = agent_session
      @payload = payload
      @occurred_at = occurred_at
    end

    def receipt_attributes
      {}
    end

    def call
      resolved_agent_session.update!(
        health_status: @payload.fetch("health_status"),
        health_metadata: @payload.fetch("health_metadata", {}),
        auto_resume_eligible: @payload.fetch("auto_resume_eligible", resolved_agent_session.auto_resume_eligible),
        unavailability_reason: @payload["unavailability_reason"],
        last_heartbeat_at: @occurred_at,
        last_health_check_at: @occurred_at
      )
    end

    private

    def resolved_agent_session
      @resolved_agent_session ||= @agent_session || @deployment.active_agent_session || @deployment.most_recent_agent_session ||
        raise(ActiveRecord::RecordNotFound, "Couldn't find AgentSession")
    end
  end
end
